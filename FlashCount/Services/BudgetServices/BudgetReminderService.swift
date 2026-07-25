import Foundation

struct BudgetReminder {
    let analysis: BudgetAnalysis
    let title: String
    let message: String
    let shortMessage: String
    let iconName: String

    var alertLevel: BudgetAlertLevel { analysis.alertLevel }
    var shouldSurfaceAfterSave: Bool { alertLevel != .healthy }
}

enum BudgetReminderService {
    static func currentBudget(in budgets: [Budget], ledger: Ledger?, referenceDate: Date = Date(), payday: Int = 1) -> Budget? {
        let cycle = PayCycleService.cycle(containing: referenceDate, payday: payday)
        let year = cycle.budgetYear
        let month = cycle.budgetMonth

        let cycleBudgets = budgets.filter { budget in
            budget.year == year
            && budget.month == month
            && budget.categoryId == nil
        }

        let matchingBudgets: [Budget]
        if let ledger {
            matchingBudgets = cycleBudgets.filter { $0.ledger?.id == ledger.id }
        } else {
            matchingBudgets = cycleBudgets.filter { $0.ledger == nil }
        }

        return matchingBudgets.sorted { $0.createdAt > $1.createdAt }.first
    }

    static func monthlySpent(in transactions: [Transaction], ledger: Ledger?, referenceDate: Date = Date(), payday: Int = 1) -> Decimal {
        let cycle = PayCycleService.cycle(containing: referenceDate, payday: payday)
        return transactions
            .filter {
                $0.isExpense
                && $0.date >= cycle.start
                && $0.date < cycle.end
                && (ledger == nil || $0.ledger?.id == ledger?.id)
                && BudgetScope.includesInDailyBudget($0)
            }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    static func monthlyExcludedSpent(in transactions: [Transaction], ledger: Ledger?, referenceDate: Date = Date(), payday: Int = 1) -> Decimal {
        let cycle = PayCycleService.cycle(containing: referenceDate, payday: payday)
        return transactions
            .filter {
                $0.isExpense
                && $0.date >= cycle.start
                && $0.date < cycle.end
                && (ledger == nil || $0.ledger?.id == ledger?.id)
                && !BudgetScope.includesInDailyBudget($0)
            }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    static func reminder(
        budgets: [Budget],
        transactions: [Transaction],
        ledger: Ledger?,
        referenceDate: Date = Date(),
        payday: Int = 1,
        weekendMultiplier: Decimal = 1
    ) -> BudgetReminder? {
        let cycle = PayCycleService.cycle(containing: referenceDate, payday: payday)
        guard let budget = currentBudget(in: budgets, ledger: ledger, referenceDate: referenceDate, payday: payday) else { return nil }
        let spent = monthlySpent(in: transactions, ledger: ledger, referenceDate: referenceDate, payday: payday)
        let excludedSpent = monthlyExcludedSpent(in: transactions, ledger: ledger, referenceDate: referenceDate, payday: payday)
        let analysis = BudgetAnalyzer.analyze(
            budgetLimit: budget.monthlyLimit,
            totalSpent: spent,
            excludedSpent: excludedSpent,
            referenceDate: referenceDate,
            periodStart: cycle.start,
            periodEnd: cycle.end,
            weekendMultiplier: weekendMultiplier
        )
        return reminder(for: analysis)
    }

    static func reminder(for analysis: BudgetAnalysis) -> BudgetReminder {
        switch analysis.alertLevel {
        case .healthy:
            return BudgetReminder(
                analysis: analysis,
                title: "日常预算健康",
                message: "本发薪周期日常消费节奏不错，剩余 \(analysis.remainingBudget.formattedCurrency)，今天可花 \(analysis.dailyAllowance.formattedCurrency)\(analysis.weekendAllowanceNote)。",
                shortMessage: "日常预算健康，今天可花 \(analysis.dailyAllowance.formattedCurrency)\(analysis.weekendAllowanceNote)",
                iconName: "checkmark.shield.fill"
            )
        case .warning:
            return BudgetReminder(
                analysis: analysis,
                title: "注意日常消费节奏",
                message: "按当前日常消费速度，本发薪周期预计花到 \(analysis.projectedTotal.formattedCurrency)。剩余 \(analysis.daysRemaining) 天，今天建议不超过 \(analysis.dailyAllowance.formattedCurrency)\(analysis.weekendAllowanceNote)。",
                shortMessage: "注意日常预算，今天建议不超过 \(analysis.dailyAllowance.formattedCurrency)\(analysis.weekendAllowanceNote)",
                iconName: "exclamationmark.triangle.fill"
            )
        case .danger:
            let overText = analysis.projectedOverAmount > 0
                ? "预计超支 \(analysis.projectedOverAmount.formattedCurrency)"
                : "预算已经用完"
            return BudgetReminder(
                analysis: analysis,
                title: "日常预算危险",
                message: "\(overText)。剩余 \(analysis.daysRemaining) 天，今天建议控制在 \(analysis.dailyAllowance.formattedCurrency)\(analysis.weekendAllowanceNote)。",
                shortMessage: "日常预算危险，\(overText)",
                iconName: "flame.fill"
            )
        }
    }
}

enum BudgetScope {
    /// 日常预算只覆盖高频、可控的小额消费。服饰、聚餐、长途出行和耐用品默认排除。
    private static let legacyIncludedCategoryNames: Set<String> = [
        "餐饮", "正餐", "外卖", "早餐", "奶茶", "咖啡", "零食", "水果", "饮料",
        "出行", "公交地铁", "打车", "共享单车", "停车过路", "加油充电",
        "日用品", "美妆个护",
    ]

    private static let includedDefaultKeys = Set(
        legacyIncludedCategoryNames.map { Category.defaultKey(for: $0, isExpense: true) }
    )

    static let description = "默认统计餐饮、通勤和日用品；服饰鞋包、聚餐、长途出行、固定账单及大件消费不计入。范围可以自行调整，每笔支出也能单独覆盖。"

    static func includesInDailyBudget(_ transaction: Transaction) -> Bool {
        guard transaction.isExpense else { return false }
        if let override = transaction.dailyBudgetOverride { return override }
        guard let category = transaction.category else { return false }
        return includesCategory(category)
    }

    static func includesCategory(_ category: Category?) -> Bool {
        guard let category, category.isExpense else { return false }
        if let override = category.dailyBudgetOverride { return override }
        return defaultIncludesCategory(category)
    }

    static func defaultIncludesCategory(_ category: Category?) -> Bool {
        guard let category,
              category.isExpense,
              let defaultKey = category.defaultKey else { return false }
        return includedDefaultKeys.contains(defaultKey)
    }

    /// Migration-only compatibility for categories persisted before `defaultKey`.
    /// Normal scope evaluation must use `includesCategory(_:)` instead.
    static func legacyIncludesCategory(named name: String) -> Bool {
        legacyIncludedCategoryNames.contains(name)
    }
}
