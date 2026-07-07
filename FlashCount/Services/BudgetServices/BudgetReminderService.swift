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
        payday: Int = 1
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
            periodEnd: cycle.end
        )
        return reminder(for: analysis)
    }

    static func reminder(for analysis: BudgetAnalysis) -> BudgetReminder {
        switch analysis.alertLevel {
        case .healthy:
            return BudgetReminder(
                analysis: analysis,
                title: "日常预算健康",
                message: "本发薪周期日常消费节奏不错，剩余 \(analysis.remainingBudget.formattedCurrency)，今天可花 \(analysis.dailyAllowance.formattedCurrency)。",
                shortMessage: "日常预算健康，今天可花 \(analysis.dailyAllowance.formattedCurrency)",
                iconName: "checkmark.shield.fill"
            )
        case .warning:
            return BudgetReminder(
                analysis: analysis,
                title: "注意日常消费节奏",
                message: "按当前日常消费速度，本发薪周期预计花到 \(analysis.projectedTotal.formattedCurrency)。剩余 \(analysis.daysRemaining) 天，建议每天不超过 \(analysis.dailyAllowance.formattedCurrency)。",
                shortMessage: "注意日常预算，今天建议不超过 \(analysis.dailyAllowance.formattedCurrency)",
                iconName: "exclamationmark.triangle.fill"
            )
        case .danger:
            let overText = analysis.projectedOverAmount > 0
                ? "预计超支 \(analysis.projectedOverAmount.formattedCurrency)"
                : "预算已经用完"
            return BudgetReminder(
                analysis: analysis,
                title: "日常预算危险",
                message: "\(overText)。剩余 \(analysis.daysRemaining) 天，接下来每天建议控制在 \(analysis.dailyAllowance.formattedCurrency)。",
                shortMessage: "日常预算危险，\(overText)",
                iconName: "flame.fill"
            )
        }
    }
}

enum BudgetScope {
    private static let includedRootNames: Set<String> = [
        "餐饮",
        "出行",
        "购物",
    ]

    private static let excludedCategoryNames: Set<String> = [
        "数码配件",
        "家具家电",
        "大件消费",
    ]

    static let description = "仅统计餐饮、出行、日常购物；房租、固定服务、娱乐、健康、学习、旅行、账务和大件/数码消费不计入预算。"

    static func includesInDailyBudget(_ transaction: Transaction) -> Bool {
        guard transaction.isExpense else { return false }
        guard let category = transaction.category else { return false }
        guard includedRootNames.contains(category.rootCategoryName) else { return false }
        return !excludedCategoryNames.contains(category.name)
    }
}
