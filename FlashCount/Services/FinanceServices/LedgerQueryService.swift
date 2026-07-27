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
        categoryID != nil || categoryRootName != nil || searchText?.isEmpty == false
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

/// 账本页顶部的收支合计。`hasHiddenIncome` 为真时收入与结余要显示为遮挡态——
/// 隐私锁生效时，露出合计等于露出收入。
struct LedgerSummary: Sendable {
    let expense: Decimal
    let income: Decimal
    let hasHiddenIncome: Bool
}

/// 后台查询只把持久化引用和业务 ID 带回主线程，避免把整批 SwiftData 对象
/// 或完整历史数组跨 actor 传递。
struct LedgerPageReference: Sendable {
    let persistentIDs: [PersistentIdentifier]
    let transactionIDs: [UUID]
    let offset: Int
    let totalCount: Int

    var hasMore: Bool {
        offset + persistentIDs.count < totalCount
    }
}

/// 账本查询的单一入口。日期、类型和金额交给 SwiftData 下推；分类和关键词
/// 需要读取关系或文本时，在服务内部完成扫描，视图只持有当前页对象。
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
            let matches = try fetchAllMatching(filter: filter)
            let page = Array(matches.dropFirst(safeOffset).prefix(safeLimit))
            return LedgerPage(transactions: page, offset: safeOffset, totalCount: matches.count)
        }

        var descriptor = makeDescriptor(filter: filter)
        descriptor.fetchLimit = safeLimit
        descriptor.fetchOffset = safeOffset
        let page = try modelContext.fetch(descriptor)
        let totalCount = try fetchCount(filter: filter)
        return LedgerPage(transactions: page, offset: safeOffset, totalCount: totalCount)
    }

    func fetchCount(filter: LedgerFilter) throws -> Int {
        if filter.requiresPostFilter {
            return try fetchAllMatching(filter: filter).count
        }
        var descriptor = makeDescriptor(filter: filter)
        descriptor.fetchLimit = nil
        descriptor.fetchOffset = 0
        return try modelContext.fetchCount(descriptor)
    }

    func fetchMatchingIDs(filter: LedgerFilter) throws -> Set<UUID> {
        Set(try fetchAllMatching(filter: filter).map(\.id))
    }

    func fetchTransactions(ids: Set<UUID>) throws -> [Transaction] {
        guard !ids.isEmpty else { return [] }
        // 只在用户确认批量删除后按 ID 取对象；正常列表和“全选”只保留 ID。
        return try modelContext.fetch(FetchDescriptor<Transaction>()).filter { ids.contains($0.id) }
    }

    func summary(filter: LedgerFilter) throws -> LedgerSummary {
        let matches = try fetchAllMatching(filter: filter)
        var expense: Decimal = 0
        var income: Decimal = 0
        var hasHiddenIncome = false
        for transaction in matches {
            if transaction.isExpense {
                expense += transaction.amount
            } else {
                income += transaction.amount
                if isIncomeHidden(transaction, isUnlocked: filter.includeProtectedIncomeMetadata) {
                    hasHiddenIncome = true
                }
            }
        }
        return LedgerSummary(expense: expense, income: income, hasHiddenIncome: hasHiddenIncome)
    }

    private func fetchAllMatching(filter: LedgerFilter) throws -> [Transaction] {
        let transactions = try modelContext.fetch(makeDescriptor(filter: filter))
        let matches = transactions.filter { matchesPostFilter($0, filter: filter) }
        return matches.sorted { sort($0, $1, filter: filter) }
    }

    private func makeDescriptor(filter: LedgerFilter) -> FetchDescriptor<Transaction> {
        let start = filter.startDate ?? .distantPast
        let end = filter.endDate ?? .distantFuture
        let minimum = filter.minAmount ?? .zero
        let maximum = filter.maxAmount ?? Decimal(string: "999999999999999999999999999999999999")!
        let hasMinimum = filter.minAmount != nil
        let hasMaximum = filter.maxAmount != nil

        var descriptor: FetchDescriptor<Transaction>
        if let isExpense = filter.isExpense {
            descriptor = FetchDescriptor(
                predicate: #Predicate<Transaction> { transaction in
                    transaction.date >= start && transaction.date < end
                        && transaction.isExpense == isExpense
                        && (!hasMinimum || transaction.amount >= minimum)
                        && (!hasMaximum || transaction.amount <= maximum)
                }
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate<Transaction> { transaction in
                    transaction.date >= start && transaction.date < end
                        && (!hasMinimum || transaction.amount >= minimum)
                        && (!hasMaximum || transaction.amount <= maximum)
                }
            )
        }

        switch (filter.sortField, filter.sortDirection) {
        case (.date, .ascending):
            descriptor.sortBy = [
                SortDescriptor(\.date, order: .forward),
                SortDescriptor(\.createdAt, order: .forward)
            ]
        case (.date, .descending):
            descriptor.sortBy = [
                SortDescriptor(\.date, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ]
        case (.amount, .ascending):
            descriptor.sortBy = [
                SortDescriptor(\.amount, order: .forward),
                SortDescriptor(\.date, order: .forward)
            ]
        case (.amount, .descending):
            descriptor.sortBy = [
                SortDescriptor(\.amount, order: .reverse),
                SortDescriptor(\.date, order: .reverse)
            ]
        }
        return descriptor
    }

    private func matchesPostFilter(_ transaction: Transaction, filter: LedgerFilter) -> Bool {
        if let categoryID = filter.categoryID, transaction.category?.id != categoryID {
            return false
        }
        if let categoryRootName = filter.categoryRootName,
           transaction.category?.rootCategoryName != categoryRootName {
            return false
        }
        guard let searchText = filter.searchText, !searchText.isEmpty else { return true }
        guard filter.includeProtectedIncomeMetadata || !transaction.isProtectedIncome else { return false }

        let query = searchText.lowercased()
        return transaction.note.lowercased().contains(query)
            || transaction.category?.name.lowercased().contains(query) == true
            || transaction.category?.rootCategoryName.lowercased().contains(query) == true
            || "\(transaction.amount)".contains(query)
    }

    private func sort(_ lhs: Transaction, _ rhs: Transaction, filter: LedgerFilter) -> Bool {
        switch filter.sortField {
        case .date:
            if lhs.date != rhs.date {
                return filter.sortDirection == .ascending ? lhs.date < rhs.date : lhs.date > rhs.date
            }
            if lhs.createdAt != rhs.createdAt {
                return filter.sortDirection == .ascending ? lhs.createdAt < rhs.createdAt : lhs.createdAt > rhs.createdAt
            }
        case .amount:
            if lhs.amount != rhs.amount {
                return filter.sortDirection == .ascending ? lhs.amount < rhs.amount : lhs.amount > rhs.amount
            }
            if lhs.date != rhs.date {
                return filter.sortDirection == .ascending ? lhs.date < rhs.date : lhs.date > rhs.date
            }
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func isIncomeHidden(_ transaction: Transaction, isUnlocked: Bool) -> Bool {
        PrivacyVisibilityPolicy.hidesIncome(
            isExpense: transaction.isExpense,
            isUnlocked: isUnlocked
        )
    }
}

/// 账本列表的后台查询入口。关键词和分类需要扫描关系字段时，也在这个
/// ModelActor 中完成，主线程只负责把当前页的持久化引用 materialize 成视图对象。
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
            let matches = try fetchAllMatching(filter: filter)
            let page = Array(matches.dropFirst(safeOffset).prefix(safeLimit))
            return LedgerPageReference(
                persistentIDs: page.map(\.persistentModelID),
                transactionIDs: page.map(\.id),
                offset: safeOffset,
                totalCount: matches.count
            )
        }

        var descriptor = makeDescriptor(filter: filter)
        descriptor.fetchLimit = safeLimit
        descriptor.fetchOffset = safeOffset
        let page = try modelContext.fetch(descriptor)
        let totalCount = try fetchCount(filter: filter)
        return LedgerPageReference(
            persistentIDs: page.map(\.persistentModelID),
            transactionIDs: page.map(\.id),
            offset: safeOffset,
            totalCount: totalCount
        )
    }

    func fetchMatchingTransactionIDs(filter: LedgerFilter) throws -> Set<UUID> {
        Set(try fetchAllMatching(filter: filter).map(\.id))
    }

    func summary(filter: LedgerFilter) throws -> LedgerSummary {
        let matches = try fetchAllMatching(filter: filter)
        var expense: Decimal = 0
        var income: Decimal = 0
        var hasHiddenIncome = false
        for transaction in matches {
            if transaction.isExpense {
                expense += transaction.amount
            } else {
                income += transaction.amount
                if isIncomeHidden(transaction, isUnlocked: filter.includeProtectedIncomeMetadata) {
                    hasHiddenIncome = true
                }
            }
        }
        return LedgerSummary(expense: expense, income: income, hasHiddenIncome: hasHiddenIncome)
    }

    private func fetchCount(filter: LedgerFilter) throws -> Int {
        if filter.requiresPostFilter {
            return try fetchAllMatching(filter: filter).count
        }
        var descriptor = makeDescriptor(filter: filter)
        descriptor.fetchLimit = nil
        descriptor.fetchOffset = 0
        return try modelContext.fetchCount(descriptor)
    }

    private func fetchAllMatching(filter: LedgerFilter) throws -> [Transaction] {
        let transactions = try modelContext.fetch(makeDescriptor(filter: filter))
        let matches = transactions.filter { matchesPostFilter($0, filter: filter) }
        return matches.sorted { sort($0, $1, filter: filter) }
    }

    private func makeDescriptor(filter: LedgerFilter) -> FetchDescriptor<Transaction> {
        let start = filter.startDate ?? .distantPast
        let end = filter.endDate ?? .distantFuture
        let minimum = filter.minAmount ?? .zero
        let maximum = filter.maxAmount ?? Decimal(string: "999999999999999999999999999999999999")!
        let hasMinimum = filter.minAmount != nil
        let hasMaximum = filter.maxAmount != nil

        var descriptor: FetchDescriptor<Transaction>
        if let isExpense = filter.isExpense {
            descriptor = FetchDescriptor(
                predicate: #Predicate<Transaction> { transaction in
                    transaction.date >= start && transaction.date < end
                        && transaction.isExpense == isExpense
                        && (!hasMinimum || transaction.amount >= minimum)
                        && (!hasMaximum || transaction.amount <= maximum)
                }
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate<Transaction> { transaction in
                    transaction.date >= start && transaction.date < end
                        && (!hasMinimum || transaction.amount >= minimum)
                        && (!hasMaximum || transaction.amount <= maximum)
                }
            )
        }

        switch (filter.sortField, filter.sortDirection) {
        case (.date, .ascending):
            descriptor.sortBy = [
                SortDescriptor(\.date, order: .forward),
                SortDescriptor(\.createdAt, order: .forward)
            ]
        case (.date, .descending):
            descriptor.sortBy = [
                SortDescriptor(\.date, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ]
        case (.amount, .ascending):
            descriptor.sortBy = [
                SortDescriptor(\.amount, order: .forward),
                SortDescriptor(\.date, order: .forward)
            ]
        case (.amount, .descending):
            descriptor.sortBy = [
                SortDescriptor(\.amount, order: .reverse),
                SortDescriptor(\.date, order: .reverse)
            ]
        }
        return descriptor
    }

    private func matchesPostFilter(_ transaction: Transaction, filter: LedgerFilter) -> Bool {
        if let categoryID = filter.categoryID, transaction.category?.id != categoryID {
            return false
        }
        if let categoryRootName = filter.categoryRootName,
           transaction.category?.rootCategoryName != categoryRootName {
            return false
        }
        guard let searchText = filter.searchText, !searchText.isEmpty else { return true }
        guard filter.includeProtectedIncomeMetadata || !transaction.isProtectedIncome else { return false }

        let query = searchText.lowercased()
        return transaction.note.lowercased().contains(query)
            || transaction.category?.name.lowercased().contains(query) == true
            || transaction.category?.rootCategoryName.lowercased().contains(query) == true
            || "\(transaction.amount)".contains(query)
    }

    private func sort(_ lhs: Transaction, _ rhs: Transaction, filter: LedgerFilter) -> Bool {
        switch filter.sortField {
        case .date:
            if lhs.date != rhs.date {
                return filter.sortDirection == .ascending ? lhs.date < rhs.date : lhs.date > rhs.date
            }
            if lhs.createdAt != rhs.createdAt {
                return filter.sortDirection == .ascending ? lhs.createdAt < rhs.createdAt : lhs.createdAt > rhs.createdAt
            }
        case .amount:
            if lhs.amount != rhs.amount {
                return filter.sortDirection == .ascending ? lhs.amount < rhs.amount : lhs.amount > rhs.amount
            }
            if lhs.date != rhs.date {
                return filter.sortDirection == .ascending ? lhs.date < rhs.date : lhs.date > rhs.date
            }
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func isIncomeHidden(_ transaction: Transaction, isUnlocked: Bool) -> Bool {
        PrivacyVisibilityPolicy.hidesIncome(
            isExpense: transaction.isExpense,
            isUnlocked: isUnlocked
        )
    }
}
