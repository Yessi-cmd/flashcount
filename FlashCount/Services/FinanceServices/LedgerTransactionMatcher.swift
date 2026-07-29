import Foundation

/// 账本查询在数据库候选集与界面呈现之间共享的最终匹配语义。
///
/// SwiftData 能下推日期、类型、金额、备注和具体分类；根分类与隐私元数据
/// 仍需读取模型关系。所有出口都通过这里做最后确认，避免列表、汇总和下钻
/// 对同一个关键词给出不同结果。
enum LedgerTransactionMatcher {
    static func matches(_ transaction: Transaction, filter: LedgerFilter) -> Bool {
        if let categoryID = filter.categoryID,
           transaction.category?.id != categoryID {
            return false
        }
        if let categoryRootName = filter.categoryRootName,
           transaction.category?.rootCategoryName != categoryRootName {
            return false
        }
        guard let searchText = normalizedSearchText(filter.searchText) else {
            return true
        }
        return matchesSearch(
            transaction,
            query: searchText,
            includeProtectedIncomeMetadata: filter.includeProtectedIncomeMetadata
        )
    }

    static func matchesSearch(
        _ transaction: Transaction,
        query: String,
        includeProtectedIncomeMetadata: Bool
    ) -> Bool {
        guard includeProtectedIncomeMetadata || !transaction.isProtectedIncome else {
            return false
        }

        let amountMatches: Bool
        if let exactAmount = Decimal(string: query) {
            amountMatches = transaction.amount == exactAmount
        } else {
            amountMatches = transaction.amount.formattedAmount.localizedStandardContains(query)
        }

        return transaction.note.localizedStandardContains(query)
            || transaction.category?.name.localizedStandardContains(query) == true
            || transaction.category?.rootCategoryName.localizedStandardContains(query) == true
            || amountMatches
    }

    static func categoryMatchesSearch(_ category: Category, query: String) -> Bool {
        category.name.localizedStandardContains(query)
            || category.rootCategoryName.localizedStandardContains(query)
    }

    static func sort(
        _ lhs: Transaction,
        _ rhs: Transaction,
        filter: LedgerFilter
    ) -> Bool {
        switch filter.sortField {
        case .date:
            if lhs.date != rhs.date {
                return filter.sortDirection == .ascending ? lhs.date < rhs.date : lhs.date > rhs.date
            }
            if lhs.createdAt != rhs.createdAt {
                return filter.sortDirection == .ascending
                    ? lhs.createdAt < rhs.createdAt
                    : lhs.createdAt > rhs.createdAt
            }
        case .amount:
            if lhs.amount != rhs.amount {
                return filter.sortDirection == .ascending
                    ? lhs.amount < rhs.amount
                    : lhs.amount > rhs.amount
            }
            if lhs.date != rhs.date {
                return filter.sortDirection == .ascending ? lhs.date < rhs.date : lhs.date > rhs.date
            }
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    static func summary(
        of transactions: [Transaction],
        includeProtectedIncomeMetadata: Bool
    ) -> LedgerSummary {
        var expense: Decimal = 0
        var income: Decimal = 0
        var hasHiddenIncome = false

        for transaction in transactions {
            if transaction.isExpense {
                expense += transaction.amount
            } else {
                income += transaction.amount
                if PrivacyVisibilityPolicy.hidesIncome(
                    isExpense: false,
                    isUnlocked: includeProtectedIncomeMetadata
                ) {
                    hasHiddenIncome = true
                }
            }
        }
        return LedgerSummary(
            expense: expense,
            income: income,
            hasHiddenIncome: hasHiddenIncome
        )
    }

    static func normalizedSearchText(_ searchText: String?) -> String? {
        guard let trimmed = searchText?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
