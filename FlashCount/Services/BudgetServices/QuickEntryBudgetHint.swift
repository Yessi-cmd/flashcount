import Foundation

/// 快速记账页当前草稿中与预算有关的信息。
struct QuickEntryBudgetDraft {
    let amount: Decimal?
    let isExpense: Bool
    let category: Category?
    let dailyBudgetOverride: Bool?
}

/// 快速记账页顶部要显示的预算提示。
struct QuickEntryBudgetHint {
    let projectedAnalysis: BudgetAnalysis
    let enteredAmount: Decimal?
    let draftCountsTowardDailyBudget: Bool

    var level: BudgetAlertLevel { projectedAnalysis.alertLevel }

    /// 一行讲清「现在还能花多少」以及正在输入的这笔会带来什么变化。
    var text: String {
        let remaining = projectedAnalysis.remainingBudget
        let allowance = projectedAnalysis.dailyAllowance

        if let enteredAmount, enteredAmount > 0 {
            if draftCountsTowardDailyBudget {
                if remaining < 0 {
                    return "记后日常预算超 \((-remaining).formattedCurrency)"
                }
                return "记后剩 \(remaining.formattedCurrency) · 今日可花 \(allowance.formattedCurrency)"
            }
            return "不计入日常预算 · 今日可花 \(allowance.formattedCurrency)"
        }

        if remaining < 0 {
            return "日常预算已超 \((-remaining).formattedCurrency)"
        }
        return "今日可花 \(allowance.formattedCurrency) · 本周期剩 \(remaining.formattedCurrency)"
    }
}

/// 预算提示的纯计算。输入金额变化时重算一次，金额输入本身不需要进
/// SwiftData，保持记账页响应轻快。
enum QuickEntryBudgetHintCalculator {
    static func makeHint(
        budgets: [Budget],
        transactions: [Transaction],
        ledger: Ledger?,
        referenceDate: Date,
        payday: Int,
        weekendMultiplier: Decimal,
        draft: QuickEntryBudgetDraft,
        calendar: Calendar = .current
    ) -> QuickEntryBudgetHint? {
        guard draft.isExpense else { return nil }
        guard let budget = BudgetReminderService.currentBudget(
            in: budgets,
            ledger: ledger,
            referenceDate: referenceDate,
            payday: payday,
            calendar: calendar
        ) else {
            return nil
        }

        let cycle = PayCycleService.cycle(
            containing: referenceDate,
            payday: payday,
            calendar: calendar
        )
        let currentSpent = BudgetReminderService.monthlySpent(
            in: transactions,
            ledger: ledger,
            referenceDate: referenceDate,
            payday: payday,
            calendar: calendar
        )
        let currentExcludedSpent = BudgetReminderService.monthlyExcludedSpent(
            in: transactions,
            ledger: ledger,
            referenceDate: referenceDate,
            payday: payday,
            calendar: calendar
        )
        var projectedSpent = currentSpent
        var projectedExcludedSpent = currentExcludedSpent
        let enteredAmount = draft.amount.flatMap { $0 > 0 ? $0 : nil }
        let countsTowardDailyBudget = Self.draftCountsTowardDailyBudget(
            isExpense: draft.isExpense,
            category: draft.category,
            dailyBudgetOverride: draft.dailyBudgetOverride
        )

        if let enteredAmount {
            if countsTowardDailyBudget {
                projectedSpent += enteredAmount
            } else {
                projectedExcludedSpent += enteredAmount
            }
        }

        let projectedAnalysis = BudgetAnalyzer.analyze(
            budgetLimit: budget.monthlyLimit,
            totalSpent: projectedSpent,
            excludedSpent: projectedExcludedSpent,
            referenceDate: referenceDate,
            periodStart: cycle.start,
            periodEnd: cycle.end,
            weekendMultiplier: weekendMultiplier,
            calendar: calendar
        )

        return QuickEntryBudgetHint(
            projectedAnalysis: projectedAnalysis,
            enteredAmount: enteredAmount,
            draftCountsTowardDailyBudget: countsTowardDailyBudget
        )
    }

    static func draftCountsTowardDailyBudget(
        isExpense: Bool,
        category: Category?,
        dailyBudgetOverride: Bool?
    ) -> Bool {
        guard isExpense else { return false }
        if let dailyBudgetOverride { return dailyBudgetOverride }
        return BudgetScope.includesCategory(category)
    }

}
