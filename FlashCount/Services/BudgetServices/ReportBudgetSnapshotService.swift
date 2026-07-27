import Foundation

/// 报表用的预算快照（持有 `Budget` 模型，仅限主线程使用）。
/// 跨 actor 传递请用 `ReportBudgetSnapshotValue`。
struct ReportBudgetSnapshot {
    let cycle: PayCycle
    let cutoff: Date
    let budget: Budget?
    let analysis: BudgetAnalysis?
}

/// 报表后台任务使用的预算值快照，不跨 actor 携带 Budget 模型对象。
struct ReportBudgetSnapshotValue: Sendable {
    let cycle: PayCycle
    let cutoff: Date
    let budgetLimit: Decimal?
    let analysis: BudgetAnalysis?
}

/// 为报表计算预算进度。
///
/// 截止时刻取决于报表是否「进行中」：当前周期算到此刻，已结束的周期算到
/// 周期最后一天，否则历史报表会显示成「还剩很多天没花完」。
enum ReportBudgetSnapshotService {
    static func snapshotValue(
        budgets: [ReportBudgetInputSnapshot],
        transactions: [ReportTransactionSnapshot],
        reportRange: ReportDateRange,
        target: ReportTarget,
        payday: Int,
        calendar: Calendar = .current,
        weekendMultiplier: Decimal = 1
    ) -> ReportBudgetSnapshotValue {
        let anchor = target.isCurrent
            ? reportRange.end
            : ReportDateRangeFormatter(calendar: calendar).inclusiveEndDate(for: reportRange)
        let cycle = PayCycleService.cycle(containing: anchor, payday: payday, calendar: calendar)
        let cutoff = min(cycle.end, reportRange.end)
        let budget = budgets
            .filter {
                $0.year == cycle.budgetYear
                    && $0.month == cycle.budgetMonth
                    && $0.categoryID == nil
                    && $0.ledgerID == nil
            }
            .sorted { $0.createdAt > $1.createdAt }
            .first

        guard let budget else {
            return ReportBudgetSnapshotValue(cycle: cycle, cutoff: cutoff, budgetLimit: nil, analysis: nil)
        }

        let spent = transactions.reduce(into: Decimal.zero) { total, transaction in
            guard transaction.isExpense,
                  transaction.date >= cycle.start,
                  transaction.date < cutoff,
                  transaction.isIncludedInDailyBudget else { return }
            total += transaction.amount
        }
        let excluded = transactions.reduce(into: Decimal.zero) { total, transaction in
            guard transaction.isExpense,
                  transaction.date >= cycle.start,
                  transaction.date < cutoff,
                  !transaction.isIncludedInDailyBudget else { return }
            total += transaction.amount
        }
        let analysis = BudgetAnalyzer.analyze(
            budgetLimit: budget.monthlyLimit,
            totalSpent: spent,
            excludedSpent: excluded,
            referenceDate: anchor,
            periodStart: cycle.start,
            periodEnd: cycle.end,
            weekendMultiplier: weekendMultiplier,
            calendar: calendar
        )
        return ReportBudgetSnapshotValue(
            cycle: cycle,
            cutoff: cutoff,
            budgetLimit: budget.monthlyLimit,
            analysis: analysis
        )
    }

    static func snapshot(
        budgets: [Budget],
        transactions: [Transaction],
        reportRange: ReportDateRange,
        target: ReportTarget,
        payday: Int,
        calendar: Calendar = .current,
        weekendMultiplier: Decimal = 1
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
            payday: payday,
            calendar: calendar
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
            periodEnd: cycle.end,
            weekendMultiplier: weekendMultiplier,
            calendar: calendar
        )
        return ReportBudgetSnapshot(cycle: cycle, cutoff: cutoff, budget: budget, analysis: analysis)
    }
}
