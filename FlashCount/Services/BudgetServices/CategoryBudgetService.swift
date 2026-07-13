import Foundation

struct CategoryBudgetSnapshot: Identifiable {
    var id: UUID { budget.id }

    let budget: Budget
    let category: Category
    let analysis: BudgetAnalysis

    var alertLevel: BudgetAlertLevel { analysis.alertLevel }

    var shortMessage: String {
        let used = Int(min(max(analysis.usagePercent, 0), 99.99) * 100)
        switch alertLevel {
        case .healthy:
            return "\(category.name)预算已用 \(used)%"
        case .warning:
            return "\(category.name)预算已用 \(used)%，剩余 \(analysis.remainingBudget.formattedCurrency)"
        case .danger:
            if analysis.remainingBudget < 0 {
                return "\(category.name)预算已超出 \((-analysis.remainingBudget).formattedCurrency)"
            }
            return "按当前节奏，\(category.name)预算预计超支"
        }
    }
}

enum CategoryBudgetService {
    static func currentBudgets(
        in budgets: [Budget],
        ledger: Ledger?,
        referenceDate: Date = Date(),
        payday: Int = 1,
        calendar: Calendar = .current
    ) -> [Budget] {
        let cycle = PayCycleService.cycle(containing: referenceDate, payday: payday, calendar: calendar)
        let year = calendar.component(.year, from: cycle.start)
        let month = calendar.component(.month, from: cycle.start)

        var newestByCategory: [UUID: Budget] = [:]
        for budget in budgets where budget.year == year && budget.month == month {
            guard let categoryID = budget.categoryId, matchesLedger(budget, ledger: ledger) else { continue }
            if let existing = newestByCategory[categoryID], existing.createdAt >= budget.createdAt { continue }
            newestByCategory[categoryID] = budget
        }
        return Array(newestByCategory.values)
    }

    static func snapshots(
        budgets: [Budget],
        transactions: [Transaction],
        categories: [Category],
        ledger: Ledger?,
        referenceDate: Date = Date(),
        payday: Int = 1,
        calendar: Calendar = .current
    ) -> [CategoryBudgetSnapshot] {
        let cycle = PayCycleService.cycle(containing: referenceDate, payday: payday, calendar: calendar)
        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        return currentBudgets(
            in: budgets,
            ledger: ledger,
            referenceDate: referenceDate,
            payday: payday,
            calendar: calendar
        )
        .compactMap { budget -> CategoryBudgetSnapshot? in
            guard let categoryID = budget.categoryId,
                  let category = categoriesByID[categoryID],
                  category.isExpense else { return nil }
            let rootName = category.rootCategoryName
            let spent = transactions.reduce(into: Decimal.zero) { total, transaction in
                guard transaction.isExpense,
                      transaction.date >= cycle.start,
                      transaction.date < cycle.end,
                      matchesLedger(transaction, ledger: ledger),
                      transaction.category?.rootCategoryName == rootName else { return }
                total += transaction.amount
            }
            let analysis = BudgetAnalyzer.analyze(
                budgetLimit: budget.monthlyLimit,
                totalSpent: spent,
                referenceDate: referenceDate,
                periodStart: cycle.start,
                periodEnd: cycle.end
            )
            return CategoryBudgetSnapshot(budget: budget, category: category, analysis: analysis)
        }
        .sorted {
            if $0.category.sortOrder == $1.category.sortOrder {
                return $0.category.name.localizedStandardCompare($1.category.name) == .orderedAscending
            }
            return $0.category.sortOrder < $1.category.sortOrder
        }
    }

    static func snapshot(
        for transaction: Transaction,
        budgets: [Budget],
        transactions: [Transaction],
        categories: [Category],
        ledger: Ledger?,
        payday: Int = 1,
        calendar: Calendar = .current
    ) -> CategoryBudgetSnapshot? {
        guard transaction.isExpense,
              let rootName = transaction.category?.rootCategoryName else { return nil }
        return snapshots(
            budgets: budgets,
            transactions: transactions,
            categories: categories,
            ledger: ledger,
            referenceDate: transaction.date,
            payday: payday,
            calendar: calendar
        ).first { $0.category.rootCategoryName == rootName }
    }

    private static func matchesLedger(_ budget: Budget, ledger: Ledger?) -> Bool {
        if let ledger { return budget.ledger?.id == ledger.id }
        return budget.ledger == nil
    }

    private static func matchesLedger(_ transaction: Transaction, ledger: Ledger?) -> Bool {
        guard let ledger else { return true }
        return transaction.ledger?.id == ledger.id
    }
}
