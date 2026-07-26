import Foundation
import SwiftUI
import SwiftData

// MARK: - 列表呈现模型

extension LedgerView {
    /// 单次渲染所需的交易数据。筛选、月度统计、按日分组在同一遍历中完成。
    struct LedgerPresentation {
        struct MonthlySummary {
            let expense: Decimal
            let income: Decimal
            let hasHiddenIncome: Bool
        }

        struct DayGroup: Identifiable {
            let id: String
            let title: String
            let transactions: [Transaction]
            let netTotal: Decimal
            let hasHiddenIncome: Bool
        }

        let filteredTransactions: [Transaction]
        let visibleTransactionCount: Int
        let totalTransactionCount: Int
        let monthlySummary: MonthlySummary
        let dayGroups: [DayGroup]

        var hasMoreTransactions: Bool {
            visibleTransactionCount < totalTransactionCount
        }
    }

    func makePresentation() -> LedgerPresentation {
        let calendar = Calendar.current
        let now = Date()
        let range = filterState.dateFilter.dateRange(
            referenceDate: now,
            payday: payday,
            customStart: filterState.customStartDate,
            customEnd: filterState.customEndDate,
            calendar: calendar
        )
        let selectedCategory = filterState.categoryFilterId.flatMap { id in allCategories.first { $0.id == id } }
        let categoryRootName = selectedCategory?.rootCategoryName == selectedCategory?.name ? selectedCategory?.name : nil
        let categoryID = categoryRootName == nil ? selectedCategory?.id : nil
        let selectedExpenseType: Bool? = filterState.typeFilter == .all ? nil : filterState.typeFilter == .expense
        let minAmount = Decimal(string: filterState.minAmountText).flatMap { $0 > 0 ? $0 : nil }
        let maxAmount = Decimal(string: filterState.maxAmountText).flatMap { $0 > 0 ? $0 : nil }
        let searchQuery = filterState.debouncedSearchText.isEmpty ? nil : filterState.debouncedSearchText.lowercased()

        var filteredTransactions: [Transaction] = []
        var expense: Decimal = 0
        var income: Decimal = 0
        var hasHiddenIncome = false
        var visibleTransactionsByDay: [Date: [Transaction]] = [:]
        var netTotalsByDay: [Date: Decimal] = [:]
        var hiddenIncomeByDay: Set<Date> = []

        for transaction in presentationTransactions {
            guard range?.contains(transaction.date) ?? true,
                  selectedExpenseType.map({ transaction.isExpense == $0 }) ?? true,
                  categoryRootName.map({ transaction.category?.rootCategoryName == $0 }) ?? true,
                  categoryID.map({ transaction.category?.id == $0 }) ?? true,
                  minAmount.map({ transaction.amount >= $0 }) ?? true,
                  maxAmount.map({ transaction.amount <= $0 }) ?? true
            else { continue }

            if let searchQuery {
                guard !isProtectedIncomeMetadataHidden(transaction),
                      transaction.note.lowercased().contains(searchQuery)
                        || transaction.category?.name.lowercased().contains(searchQuery) == true
                        || transaction.category?.rootCategoryName.lowercased().contains(searchQuery) == true
                        || "\(transaction.amount)".contains(searchQuery)
                else { continue }
            }

            filteredTransactions.append(transaction)
            let day = calendar.startOfDay(for: transaction.date)
            netTotalsByDay[day, default: 0] += transaction.signedAmount
            if isIncomeHidden(transaction) {
                hiddenIncomeByDay.insert(day)
            }

            if transaction.isExpense {
                expense += transaction.amount
            } else {
                income += transaction.amount
                if isIncomeHidden(transaction) { hasHiddenIncome = true }
            }
        }

        filteredTransactions.sort { lhs, rhs in
            switch filterState.sortField {
            case .date:
                if lhs.date != rhs.date {
                    return filterState.sortDirection == .ascending ? lhs.date < rhs.date : lhs.date > rhs.date
                }
                if lhs.createdAt != rhs.createdAt {
                    return filterState.sortDirection == .ascending ? lhs.createdAt < rhs.createdAt : lhs.createdAt > rhs.createdAt
                }
            case .amount:
                if lhs.amount != rhs.amount {
                    return filterState.sortDirection == .ascending ? lhs.amount < rhs.amount : lhs.amount > rhs.amount
                }
                if lhs.date != rhs.date {
                    return filterState.sortDirection == .ascending ? lhs.date < rhs.date : lhs.date > rhs.date
                }
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        let visibleTransactions = filteredTransactions
        let dayGroups: [LedgerPresentation.DayGroup]
        if filterState.sortField == .date {
            for transaction in visibleTransactions {
                let day = calendar.startOfDay(for: transaction.date)
                visibleTransactionsByDay[day, default: []].append(transaction)
            }
            let orderedDays = visibleTransactionsByDay.keys.sorted {
                filterState.sortDirection == .ascending ? $0 < $1 : $0 > $1
            }
            dayGroups = orderedDays.map { day in
                LedgerPresentation.DayGroup(
                    id: "day-\(day.timeIntervalSinceReferenceDate)",
                    title: day.relativeString,
                    transactions: visibleTransactionsByDay[day] ?? [],
                    netTotal: netTotalsByDay[day] ?? 0,
                    hasHiddenIncome: hiddenIncomeByDay.contains(day)
                )
            }
        } else if visibleTransactions.isEmpty {
            dayGroups = []
        } else {
            dayGroups = [LedgerPresentation.DayGroup(
                id: "amount",
                title: filterState.sortDirection.detail(for: .amount),
                transactions: visibleTransactions,
                netTotal: filteredTransactions.reduce(0) { $0 + $1.signedAmount },
                hasHiddenIncome: filteredTransactions.contains(where: isIncomeHidden)
            )]
        }

        return LedgerPresentation(
            filteredTransactions: filteredTransactions,
            visibleTransactionCount: visibleTransactions.count,
            totalTransactionCount: totalTransactionCount,
            monthlySummary: .init(expense: expense, income: income, hasHiddenIncome: hasHiddenIncome),
            dayGroups: dayGroups
        )
    }

    var ledgerQueryID: String {
        "\(filterState.dateFilter.rawValue)-\(filterState.customStartDate.timeIntervalSinceReferenceDate)-\(filterState.customEndDate.timeIntervalSinceReferenceDate)-\(filterState.typeFilter.rawValue)-\(filterState.categoryFilterId?.uuidString ?? "all")-\(filterState.minAmountText)-\(filterState.maxAmountText)-\(filterState.debouncedSearchText)-\(filterState.sortField.rawValue)-\(filterState.sortDirection.rawValue)-\(privacyLock.isUnlocked)-\(ledgerDataDigest)"
    }

    var ledgerDataDigest: Int {
        var hasher = Hasher()
        for transaction in allTransactions {
            hasher.combine(transaction.id)
            hasher.combine(transaction.amount)
            hasher.combine(transaction.isExpense)
            hasher.combine(transaction.date)
            hasher.combine(transaction.createdAt)
            hasher.combine(transaction.note)
            hasher.combine(transaction.isPrivateIncome)
            hasher.combine(transaction.category?.id)
            hasher.combine(transaction.category?.name)
            hasher.combine(transaction.category?.rootCategoryName)
        }
        return hasher.finalize()
    }

    var currentLedgerFilter: LedgerFilter {
        let calendar = Calendar.current
        let range = filterState.dateFilter.dateRange(
            referenceDate: Date(),
            payday: payday,
            customStart: filterState.customStartDate,
            customEnd: filterState.customEndDate,
            calendar: calendar
        )
        let selectedCategory = filterState.categoryFilterId.flatMap { id in allCategories.first { $0.id == id } }
        let rootName = selectedCategory?.rootCategoryName == selectedCategory?.name
            ? selectedCategory?.name
            : nil
        let minimum = try? MoneyValidation.parse(filterState.minAmountText, requirement: .positive).get()
        let maximum = try? MoneyValidation.parse(filterState.maxAmountText, requirement: .positive).get()
        return LedgerFilter(
            startDate: range?.lowerBound,
            endDate: range?.upperBound,
            isExpense: filterState.typeFilter == .all ? nil : filterState.typeFilter == .expense,
            categoryID: rootName == nil ? selectedCategory?.id : nil,
            categoryRootName: rootName,
            minAmount: minimum,
            maxAmount: maximum,
            searchText: filterState.debouncedSearchText.isEmpty ? nil : filterState.debouncedSearchText,
            includeProtectedIncomeMetadata: privacyLock.isUnlocked,
            sortField: filterState.sortField,
            sortDirection: filterState.sortDirection
        )
    }
}
