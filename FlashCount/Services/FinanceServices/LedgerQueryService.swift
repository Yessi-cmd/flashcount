import Foundation
import SwiftData

/// 可复用的账本查询条件。分页和统计使用同一份条件，避免列表与总数出现分歧。
struct LedgerFilter: Equatable, Hashable, Sendable {
    let startDate: Date?
    let endDate: Date?
    let isExpense: Bool?
    let categoryID: UUID?
    let categoryRootName: String?
    let minAmount: Decimal?
    let maxAmount: Decimal?
    let searchText: String?
    let includeProtectedIncomeMetadata: Bool
    let sortField: TransactionSortField
    let sortDirection: TransactionSortDirection

    var requiresPostFilter: Bool {
        categoryID != nil
            || categoryRootName != nil
            || LedgerTransactionMatcher.normalizedSearchText(searchText) != nil
    }
}

/// 一页交易查询结果（主线程用，持有模型对象）。
/// 跨 actor 传递请用 `LedgerPageReference`。
struct LedgerPage {
    let transactions: [Transaction]
    let offset: Int
    let totalCount: Int

    var hasMore: Bool {
        offset + transactions.count < totalCount
    }
}

/// 账本页顶部的收支合计。`hasHiddenIncome` 为真时收入与结余要显示为遮挡态。
struct LedgerSummary: Sendable {
    let expense: Decimal
    let income: Decimal
    let hasHiddenIncome: Bool
}

/// 后台查询只把持久化引用和业务 ID 带回主线程。
struct LedgerPageReference: Sendable {
    let persistentIDs: [PersistentIdentifier]
    let transactionIDs: [UUID]
    let offset: Int
    let totalCount: Int

    var hasMore: Bool {
        offset + persistentIDs.count < totalCount
    }
}

/// 当前页和完整汇总来自同一次后台查询快照。
struct LedgerPageSnapshot: Sendable {
    let page: LedgerPageReference
    let summary: LedgerSummary
}

/// 主线程调用方的账本查询门面。视图列表优先使用下面的 `LedgerQueryDataStore`；
/// 此类型保留给用户确认后的模型 mutation 和现有领域测试。
@MainActor
final class LedgerQueryService {
    static let pageSize = 200

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchPage(
        filter: LedgerFilter,
        offset: Int,
        limit: Int = 200
    ) throws -> LedgerPage {
        let safeOffset = max(offset, 0)
        let safeLimit = max(limit, 1)

        if filter.requiresPostFilter {
            let matches = try LedgerQueryExecutor.fetchAllMatching(
                modelContext: modelContext,
                filter: filter
            )
            return LedgerPage(
                transactions: Array(matches.dropFirst(safeOffset).prefix(safeLimit)),
                offset: safeOffset,
                totalCount: matches.count
            )
        }

        var descriptor = LedgerQueryExecutor.makeDescriptor(filter: filter)
        descriptor.fetchLimit = safeLimit
        descriptor.fetchOffset = safeOffset
        return LedgerPage(
            transactions: try modelContext.fetch(descriptor),
            offset: safeOffset,
            totalCount: try LedgerQueryExecutor.fetchCount(
                modelContext: modelContext,
                filter: filter
            )
        )
    }

    func fetchCount(filter: LedgerFilter) throws -> Int {
        try LedgerQueryExecutor.fetchCount(modelContext: modelContext, filter: filter)
    }

    func fetchMatchingIDs(filter: LedgerFilter) throws -> Set<UUID> {
        Set(
            try LedgerQueryExecutor.fetchAllMatching(
                modelContext: modelContext,
                filter: filter
            ).map(\.id)
        )
    }

    func fetchTransactions(ids: Set<UUID>) throws -> [Transaction] {
        guard !ids.isEmpty else { return [] }
        // 只在用户确认批量删除后按 ID 取对象；正常列表和“全选”只保留 ID。
        return try modelContext.fetch(FetchDescriptor<Transaction>())
            .filter { ids.contains($0.id) }
    }

    func summary(filter: LedgerFilter) throws -> LedgerSummary {
        let matches = try LedgerQueryExecutor.fetchAllMatching(
            modelContext: modelContext,
            filter: filter
        )
        return LedgerTransactionMatcher.summary(
            of: matches,
            includeProtectedIncomeMetadata: filter.includeProtectedIncomeMetadata
        )
    }
}

/// 账本列表的后台查询入口。主线程只 materialize 当前页的持久化引用。
@ModelActor
actor LedgerQueryDataStore {
    func fetchPage(
        filter: LedgerFilter,
        offset: Int,
        limit: Int = 200
    ) throws -> LedgerPageReference {
        let safeOffset = max(offset, 0)
        let safeLimit = max(limit, 1)

        if filter.requiresPostFilter {
            let matches = try LedgerQueryExecutor.fetchAllMatching(
                modelContext: modelContext,
                filter: filter
            )
            return pageReference(
                from: matches,
                offset: safeOffset,
                limit: safeLimit
            )
        }

        var descriptor = LedgerQueryExecutor.makeDescriptor(filter: filter)
        descriptor.fetchLimit = safeLimit
        descriptor.fetchOffset = safeOffset
        let page = try modelContext.fetch(descriptor)
        return LedgerPageReference(
            persistentIDs: page.map(\.persistentModelID),
            transactionIDs: page.map(\.id),
            offset: safeOffset,
            totalCount: try LedgerQueryExecutor.fetchCount(
                modelContext: modelContext,
                filter: filter
            )
        )
    }

    /// Fetches and filters once, then derives both the page and summary from
    /// that immutable result. Used by the ledger's first page and report
    /// drill-down so their headline always reconciles with the listed rows.
    func fetchPageSnapshot(
        filter: LedgerFilter,
        offset: Int,
        limit: Int = 200
    ) throws -> LedgerPageSnapshot {
        let safeOffset = max(offset, 0)
        let safeLimit = max(limit, 1)
        let matches = try LedgerQueryExecutor.fetchAllMatching(
            modelContext: modelContext,
            filter: filter
        )
        return LedgerPageSnapshot(
            page: pageReference(
                from: matches,
                offset: safeOffset,
                limit: safeLimit
            ),
            summary: LedgerTransactionMatcher.summary(
                of: matches,
                includeProtectedIncomeMetadata: filter.includeProtectedIncomeMetadata
            )
        )
    }

    func fetchMatchingTransactionIDs(filter: LedgerFilter) throws -> Set<UUID> {
        try Task.checkCancellation()
        return Set(
            try LedgerQueryExecutor.fetchAllMatching(
                modelContext: modelContext,
                filter: filter
            ).map(\.id)
        )
    }

    func summary(filter: LedgerFilter) throws -> LedgerSummary {
        let matches = try LedgerQueryExecutor.fetchAllMatching(
            modelContext: modelContext,
            filter: filter
        )
        return LedgerTransactionMatcher.summary(
            of: matches,
            includeProtectedIncomeMetadata: filter.includeProtectedIncomeMetadata
        )
    }

    private func pageReference(
        from matches: [Transaction],
        offset: Int,
        limit: Int
    ) -> LedgerPageReference {
        let page = Array(matches.dropFirst(offset).prefix(limit))
        return LedgerPageReference(
            persistentIDs: page.map(\.persistentModelID),
            transactionIDs: page.map(\.id),
            offset: offset,
            totalCount: matches.count
        )
    }
}
