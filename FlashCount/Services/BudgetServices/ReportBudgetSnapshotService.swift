import Foundation

struct ReportBudgetSnapshot {
    let cycle: PayCycle
    let cutoff: Date
    let budget: Budget?
    let analysis: BudgetAnalysis?
}

enum ReportBudgetSnapshotService {
    static func snapshot(
        budgets: [Budget],
        transactions: [Transaction],
        reportRange: ReportDateRange,
        target: ReportTarget,
        payday: Int,
        calendar: Calendar = .current
    ) -> ReportBudgetSnapshot {
        let anchor = target.isCurrent
            ? reportRange.end
            : ReportDateRangeFormatter(calendar: calendar).inclusiveEndDate(for: reportRange)
        let cycle = PayCycleService.cycle(containing: anchor, payday: payday, calendar: calendar)
        let cutoff = min(cycle.end, reportRange.end)
        let budget = BudgetReminderService.currentBudget(
            in: budgets,
            ledger: nil,
            referenceDate: anchor,
            payday: payday
        )

        guard let budget else {
            return ReportBudgetSnapshot(cycle: cycle, cutoff: cutoff, budget: nil, analysis: nil)
        }

        let spent = transactions.reduce(into: Decimal.zero) { total, transaction in
            guard transaction.isExpense,
                  transaction.date >= cycle.start,
                  transaction.date < cutoff,
                  BudgetScope.includesInDailyBudget(transaction) else { return }
            total += transaction.amount
        }
        let excluded = transactions.reduce(into: Decimal.zero) { total, transaction in
            guard transaction.isExpense,
                  transaction.date >= cycle.start,
                  transaction.date < cutoff,
                  !BudgetScope.includesInDailyBudget(transaction) else { return }
            total += transaction.amount
        }
        let analysis = BudgetAnalyzer.analyze(
            budgetLimit: budget.monthlyLimit,
            totalSpent: spent,
            excludedSpent: excluded,
            referenceDate: anchor,
            periodStart: cycle.start,
            periodEnd: cycle.end
        )
        return ReportBudgetSnapshot(cycle: cycle, cutoff: cutoff, budget: budget, analysis: analysis)
    }
}
