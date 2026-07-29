import Foundation
import SwiftData

/// Executes the shared ledger query plan against a caller-owned model context.
///
/// Category relations are resolved from the small category table, then each
/// matching category is pushed into SwiftData as a concrete predicate. Keyword
/// search pushes note matching and exact numeric amount matching into the store.
/// This avoids loading an entire long-range ledger merely because one relation
/// or keyword filter is active.
enum LedgerQueryExecutor {
    static func fetchAllMatching(
        modelContext: ModelContext,
        filter: LedgerFilter
    ) throws -> [Transaction] {
        try Task.checkCancellation()
        let candidates = try fetchCandidates(modelContext: modelContext, filter: filter)
        try Task.checkCancellation()
        return candidates
            .filter { LedgerTransactionMatcher.matches($0, filter: filter) }
            .sorted { LedgerTransactionMatcher.sort($0, $1, filter: filter) }
    }

    static func fetchCount(
        modelContext: ModelContext,
        filter: LedgerFilter
    ) throws -> Int {
        if filter.requiresPostFilter {
            return try fetchAllMatching(modelContext: modelContext, filter: filter).count
        }
        var descriptor = makeDescriptor(filter: filter)
        descriptor.fetchLimit = nil
        descriptor.fetchOffset = 0
        return try modelContext.fetchCount(descriptor)
    }

    static func makeDescriptor(filter: LedgerFilter) -> FetchDescriptor<Transaction> {
        makeCandidateDescriptor(
            filter: filter,
            categoryID: nil,
            searchText: nil,
            exactAmount: nil
        )
    }

    private static func fetchCandidates(
        modelContext: ModelContext,
        filter: LedgerFilter
    ) throws -> [Transaction] {
        guard filter.requiresPostFilter else {
            return try modelContext.fetch(makeDescriptor(filter: filter))
        }

        let categories = try modelContext.fetch(FetchDescriptor<Category>())
        let explicitCategoryIDs = resolvedCategoryIDs(
            filter: filter,
            categories: categories
        )
        let searchText = LedgerTransactionMatcher.normalizedSearchText(filter.searchText)
        let exactAmount = searchText.flatMap { Decimal(string: $0) }
        var candidatesByID: [UUID: Transaction] = [:]

        if let explicitCategoryIDs {
            for categoryID in explicitCategoryIDs {
                try Task.checkCancellation()
                let categoryMatchesQuery = searchText.map { query in
                    categories
                        .first(where: { $0.id == categoryID })
                        .map { LedgerTransactionMatcher.categoryMatchesSearch($0, query: query) }
                        ?? false
                } ?? true
                let descriptor = makeCandidateDescriptor(
                    filter: filter,
                    categoryID: categoryID,
                    searchText: categoryMatchesQuery ? nil : searchText,
                    exactAmount: exactAmount
                )
                append(
                    try modelContext.fetch(descriptor),
                    to: &candidatesByID
                )
            }
            return Array(candidatesByID.values)
        }

        guard let searchText else {
            return try modelContext.fetch(makeDescriptor(filter: filter))
        }

        // Notes and exact numeric amounts can be queried directly.
        append(
            try modelContext.fetch(
                makeCandidateDescriptor(
                    filter: filter,
                    categoryID: nil,
                    searchText: searchText,
                    exactAmount: exactAmount
                )
            ),
            to: &candidatesByID
        )

        // Category names and root names are resolved from the much smaller
        // category table, then pushed down as concrete relationship IDs.
        for category in categories where
            LedgerTransactionMatcher.categoryMatchesSearch(category, query: searchText) {
            try Task.checkCancellation()
            append(
                try modelContext.fetch(
                    makeCandidateDescriptor(
                        filter: filter,
                        categoryID: category.id,
                        searchText: nil,
                        exactAmount: nil
                    )
                ),
                to: &candidatesByID
            )
        }
        return Array(candidatesByID.values)
    }

    private static func resolvedCategoryIDs(
        filter: LedgerFilter,
        categories: [Category]
    ) -> [UUID]? {
        if let categoryID = filter.categoryID {
            return [categoryID]
        }
        if let rootName = filter.categoryRootName {
            return categories
                .filter { $0.rootCategoryName == rootName }
                .map(\.id)
        }
        return nil
    }

    private static func append(
        _ transactions: [Transaction],
        to result: inout [UUID: Transaction]
    ) {
        for transaction in transactions {
            result[transaction.id] = transaction
        }
    }

    private static func makeCandidateDescriptor(
        filter: LedgerFilter,
        categoryID: UUID?,
        searchText: String?,
        exactAmount: Decimal?
    ) -> FetchDescriptor<Transaction> {
        let start = filter.startDate ?? .distantPast
        let end = filter.endDate ?? .distantFuture
        let minimum = filter.minAmount ?? .zero
        let maximum = filter.maxAmount ?? Decimal(Int.max)
        let hasMinimum = filter.minAmount != nil
        let hasMaximum = filter.maxAmount != nil
        let hasCategory = categoryID != nil
        let candidateCategoryID = categoryID ?? UUID()
        let hasSearchText = searchText != nil
        let candidateSearchText = searchText ?? ""
        let hasExactAmount = exactAmount != nil
        let candidateExactAmount = exactAmount ?? .zero

        var descriptor: FetchDescriptor<Transaction>
        if let isExpense = filter.isExpense {
            descriptor = FetchDescriptor(
                predicate: #Predicate<Transaction> { transaction in
                    transaction.date >= start && transaction.date < end
                        && transaction.isExpense == isExpense
                        && (!hasMinimum || transaction.amount >= minimum)
                        && (!hasMaximum || transaction.amount <= maximum)
                        && (!hasCategory || transaction.category?.id == candidateCategoryID)
                        && (
                            !hasSearchText
                                || transaction.note.localizedStandardContains(candidateSearchText)
                                || (hasExactAmount && transaction.amount == candidateExactAmount)
                        )
                }
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate<Transaction> { transaction in
                    transaction.date >= start && transaction.date < end
                        && (!hasMinimum || transaction.amount >= minimum)
                        && (!hasMaximum || transaction.amount <= maximum)
                        && (!hasCategory || transaction.category?.id == candidateCategoryID)
                        && (
                            !hasSearchText
                                || transaction.note.localizedStandardContains(candidateSearchText)
                                || (hasExactAmount && transaction.amount == candidateExactAmount)
                        )
                }
            )
        }

        switch (filter.sortField, filter.sortDirection) {
        case (.date, .ascending):
            descriptor.sortBy = [
                SortDescriptor(\.date, order: .forward),
                SortDescriptor(\.createdAt, order: .forward),
            ]
        case (.date, .descending):
            descriptor.sortBy = [
                SortDescriptor(\.date, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse),
            ]
        case (.amount, .ascending):
            descriptor.sortBy = [
                SortDescriptor(\.amount, order: .forward),
                SortDescriptor(\.date, order: .forward),
            ]
        case (.amount, .descending):
            descriptor.sortBy = [
                SortDescriptor(\.amount, order: .reverse),
                SortDescriptor(\.date, order: .reverse),
            ]
        }
        return descriptor
    }
}
