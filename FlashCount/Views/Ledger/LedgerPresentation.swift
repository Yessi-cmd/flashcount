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

        static let empty = LedgerPresentation(
            filteredTransactions: [],
            visibleTransactionCount: 0,
            totalTransactionCount: 0,
            monthlySummary: MonthlySummary(
                expense: 0,
                income: 0,
                hasHiddenIncome: false
            ),
            dayGroups: []
        )

        var hasMoreTransactions: Bool {
            visibleTransactionCount < totalTransactionCount
        }
    }

    func rebuildPresentation() {
        ledgerPresentation = makePresentation()
    }

    /// Builds day groups from the already-filtered current page.
    ///
    /// Filtering and sorting happen once in `LedgerQueryDataStore`; rebuilding
    /// this value is tied to page loads rather than every unrelated body update.
    func makePresentation() -> LedgerPresentation {
        let calendar = Calendar.current
        let visibleTransactions = presentationTransactions
        var expense: Decimal = 0
        var income: Decimal = 0
        var hasHiddenIncome = false
        var visibleTransactionsByDay: [Date: [Transaction]] = [:]
        var netTotalsByDay: [Date: Decimal] = [:]
        var hiddenIncomeByDay: Set<Date> = []

        for transaction in visibleTransactions {
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
                netTotal: visibleTransactions.reduce(0) { $0 + $1.signedAmount },
                hasHiddenIncome: visibleTransactions.contains(where: isIncomeHidden)
            )]
        }

        return LedgerPresentation(
            filteredTransactions: visibleTransactions,
            visibleTransactionCount: visibleTransactions.count,
            totalTransactionCount: totalTransactionCount,
            monthlySummary: .init(expense: expense, income: income, hasHiddenIncome: hasHiddenIncome),
            dayGroups: dayGroups
        )
    }

    var ledgerQueryID: String {
        "\(filterState.dateFilter.rawValue)-\(filterState.customStartDate.timeIntervalSinceReferenceDate)-\(filterState.customEndDate.timeIntervalSinceReferenceDate)-\(filterState.typeFilter.rawValue)-\(filterState.categoryFilterId?.uuidString ?? "all")-\(filterState.minAmountText)-\(filterState.maxAmountText)-\(filterState.debouncedSearchText)-\(filterState.sortField.rawValue)-\(filterState.sortDirection.rawValue)-\(privacyLock.isUnlocked)-\(ledgerDataRevision)"
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
