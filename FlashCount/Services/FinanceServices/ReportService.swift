import Foundation
import SwiftData

/// 分类消费汇总
struct CategorySpending: Identifiable {
    var id: String { categoryName }
    let categoryName: String
    let categoryIcon: String
    let categoryColor: String
    let amount: Decimal
    let percentage: Double
    let changeFromLastPeriod: Double?
}

/// 报表数据
struct ReportData {
    let period: ReportPeriod
    let target: ReportTarget
    let reportRange: ReportDateRange
    let comparisonRange: ReportDateRange
    let totalExpense: Decimal
    let totalIncome: Decimal
    let netChange: Decimal
    let expenseChange: Double?
    let incomeChange: Double?
    let hasHiddenPrivateIncome: Bool
    let categoryBreakdown: [CategorySpending]
    let timeBuckets: [ReportTimeBucket]
    let streakDays: Int
    let insights: [String]
    let transactionCount: Int
}

/// 报表服务
@MainActor
final class ReportService {
    private let modelContext: ModelContext
    private let calendar: Calendar
    private let payday: Int
    private let now: () -> Date

    init(
        modelContext: ModelContext,
        calendar: Calendar = .current,
        payday: Int = 1,
        now: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.payday = min(max(payday, 1), 31)
        self.now = now
    }

    /// 显式目标 API，定时报表应传入 ReportTarget.scheduled(period:triggerDate:)。
    func generateReport(
        period: ReportPeriod,
        target: ReportTarget,
        includePrivateIncome: Bool = true
    ) throws -> ReportData {
        let calculator = ReportPeriodCalculator(calendar: calendar, payday: payday)
        let selection = calculator.selection(for: period, target: target)
        let currentTransactions = try fetchTransactions(in: selection.reportRange)
        let comparisonTransactions = try fetchTransactions(in: selection.comparisonRange)

        let currentExpenses = currentTransactions.filter(\.isExpense)
        let comparisonExpenses = comparisonTransactions.filter(\.isExpense)
        let currentIncome = visibleIncome(in: currentTransactions, includePrivateIncome: includePrivateIncome)
        let comparisonIncome = visibleIncome(in: comparisonTransactions, includePrivateIncome: includePrivateIncome)

        let totalExpense = sum(currentExpenses)
        let totalIncome = sum(currentIncome)
        let comparisonExpense = sum(comparisonExpenses)
        let comparisonIncomeTotal = sum(comparisonIncome)
        let expenseChange = percentageChange(current: totalExpense, previous: comparisonExpense)
        let incomeChange = percentageChange(current: totalIncome, previous: comparisonIncomeTotal)

        let categoryBreakdown = buildCategoryBreakdown(
            transactions: currentExpenses,
            totalExpense: totalExpense,
            previousTransactions: comparisonExpenses
        )
        let timeBuckets = buildTimeBuckets(
            transactions: currentExpenses,
            selection: selection,
            calculator: calculator
        )
        let streakDays = try calculateStreak(throughExclusive: selection.reportRange.end)
        let insights = generateInsights(
            categoryBreakdown: categoryBreakdown,
            expenseChange: expenseChange,
            period: period,
            target: target,
            transactions: currentExpenses
        )

        return ReportData(
            period: period,
            target: target,
            reportRange: selection.reportRange,
            comparisonRange: selection.comparisonRange,
            totalExpense: totalExpense,
            totalIncome: totalIncome,
            netChange: totalIncome - totalExpense,
            expenseChange: expenseChange,
            incomeChange: incomeChange,
            hasHiddenPrivateIncome: !includePrivateIncome && currentTransactions.contains(where: \.isProtectedIncome),
            categoryBreakdown: categoryBreakdown,
            timeBuckets: timeBuckets,
            streakDays: streakDays,
            insights: insights,
            transactionCount: currentTransactions.count
        )
    }

    /// 兼容现有应用内报表：展示包含当前时刻的进行中周期。
    func generateReport(period: ReportPeriod, includePrivateIncome: Bool = true) throws -> ReportData {
        try generateReport(
            period: period,
            target: .current(referenceDate: now()),
            includePrivateIncome: includePrivateIncome
        )
    }

    private func fetchTransactions(in range: ReportDateRange) throws -> [Transaction] {
        let start = range.start
        let end = range.end
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { transaction in
                transaction.date >= start && transaction.date < end
            }
        )
        return try modelContext.fetch(descriptor)
    }

    private func visibleIncome(in transactions: [Transaction], includePrivateIncome: Bool) -> [Transaction] {
        transactions.filter { !$0.isExpense && (includePrivateIncome || !$0.isProtectedIncome) }
    }

    private func sum(_ transactions: [Transaction]) -> Decimal {
        transactions.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private func percentageChange(current: Decimal, previous: Decimal) -> Double? {
        guard previous > 0 else { return nil }
        return NSDecimalNumber(decimal: (current - previous) / previous).doubleValue
    }

    private func buildCategoryBreakdown(
        transactions: [Transaction],
        totalExpense: Decimal,
        previousTransactions: [Transaction]
    ) -> [CategorySpending] {
        let grouped = Dictionary(grouping: transactions) { $0.category?.reportDisplayName ?? "未分类" }
        let previousGrouped = Dictionary(grouping: previousTransactions) { $0.category?.reportDisplayName ?? "未分类" }

        return grouped.map { name, transactions in
            let amount = sum(transactions)
            let previousAmount = sum(previousGrouped[name] ?? [])
            let firstTransaction = transactions.first
            return CategorySpending(
                categoryName: name,
                categoryIcon: firstTransaction?.category?.reportIcon ?? "questionmark",
                categoryColor: firstTransaction?.category?.reportColorHex ?? "#667EEA",
                amount: amount,
                percentage: totalExpense > 0
                    ? NSDecimalNumber(decimal: amount / totalExpense).doubleValue
                    : 0,
                changeFromLastPeriod: percentageChange(current: amount, previous: previousAmount)
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    private func buildTimeBuckets(
        transactions: [Transaction],
        selection: ReportPeriodSelection,
        calculator: ReportPeriodCalculator
    ) -> [ReportTimeBucket] {
        calculator.bucketRanges(for: selection).map { range in
            let amount = transactions
                .filter { range.contains($0.date) }
                .reduce(Decimal.zero) { $0 + $1.amount }
            return ReportTimeBucket(
                range: range,
                granularity: selection.period.bucketGranularity,
                label: ReportDateRangeFormatter(calendar: calendar).bucketLabel(
                    for: range,
                    granularity: selection.period.bucketGranularity
                ),
                expense: amount
            )
        }
    }

    private func calculateStreak(throughExclusive end: Date) throws -> Int {
        var streak = 0
        let referenceDay: Date
        if calendar.isDate(end, equalTo: calendar.startOfDay(for: end), toGranularity: .second) {
            let previousDay = calendar.date(byAdding: .day, value: -1, to: end) ?? end
            referenceDay = calendar.startOfDay(for: previousDay)
        } else {
            referenceDay = calendar.startOfDay(for: end)
        }
        var expectedDay: Date?
        var lastProcessedDay: Date?
        var offset = 0
        let pageSize = 256

        while true {
            var descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate<Transaction> { transaction in
                    transaction.date < end
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            descriptor.fetchLimit = pageSize
            descriptor.fetchOffset = offset
            let page = try modelContext.fetch(descriptor)
            guard !page.isEmpty else { break }

            for transaction in page {
                let day = calendar.startOfDay(for: transaction.date)
                guard day != lastProcessedDay else { continue }
                lastProcessedDay = day
                if expectedDay == nil {
                    let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDay)
                    guard day == referenceDay || day == yesterday else { return 0 }
                    expectedDay = day
                }
                guard day == expectedDay else { return streak }
                streak += 1
                expectedDay = calendar.date(byAdding: .day, value: -1, to: day)
            }
            if page.count < pageSize { break }
            offset += page.count
        }
        return streak
    }

    private func generateInsights(
        categoryBreakdown: [CategorySpending],
        expenseChange: Double?,
        period: ReportPeriod,
        target: ReportTarget,
        transactions: [Transaction]
    ) -> [String] {
        var insights: [String] = []
        let periodName = target.isCurrent ? period.currentTitle : "报告期内"

        if let top = categoryBreakdown.first {
            let percentage = ReportPercentageFormatter.categoryShare(top.percentage)
            insights.append("\(periodName)\(top.categoryName)占比最高，达 \(percentage)")
            if top.percentage > 0.4 {
                insights.append("\(top.categoryName)支出集中度偏高，建议适当控制")
            }
        }

        if let change = expenseChange {
            let percentage = ReportPercentageFormatter.changeRate(change)
            if change > 0.1 {
                insights.append("\(periodName)总支出比上期增加了 \(percentage)")
            } else if change < -0.1 {
                insights.append("\(periodName)总支出比上期减少了 \(percentage)，继续保持")
            } else {
                insights.append("\(periodName)总支出与上期基本持平")
            }
        }

        for category in categoryBreakdown.prefix(3) {
            if let change = category.changeFromLastPeriod, abs(change) > 0.2 {
                let percentage = ReportPercentageFormatter.changeRate(change)
                let arrow = change > 0 ? "↑" : "↓"
                insights.append("🔍 \(category.categoryName) \(arrow) \(percentage)（对比上期）")
            }
        }

        let amounts = transactions.map(\.amount).sorted()
        if amounts.count >= 4 {
            let median = amounts[amounts.count / 2]
            if let unusual = transactions.max(by: { $0.amount < $1.amount }),
               median > 0,
               unusual.amount >= median * 3 {
                let name = unusual.category?.reportDisplayName ?? "未分类"
                insights.append("🔔 发现一笔较平时偏高的\(name)支出：\(unusual.amount.formattedCurrency)")
            }
        }

        return insights
    }
}
