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

enum ReportInsightTone: Equatable {
    case positive
    case neutral
    case attention
}

/// 可解释的本地洞察。`isSensitive` 用于让界面跟随收入隐私锁隐藏内容。
struct ReportInsight: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let tone: ReportInsightTone
    let isSensitive: Bool
}

/// 每种报表周期共用的结构化分析结果，展示层可据此组合指标和洞察。
struct ReportSmartAnalysis {
    let averageExpense: Decimal
    let averageLabel: String
    let averageDetail: String
    let peakBucket: ReportTimeBucket?
    let peakShare: Double
    let activeBucketCount: Int
    let activeBucketLabel: String
    let projectedExpense: Decimal?
    let savingsRate: Double?
    let insights: [ReportInsight]
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
    let smartAnalysis: ReportSmartAnalysis
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
        let smartAnalysis = buildSmartAnalysis(
            categoryBreakdown: categoryBreakdown,
            expenseChange: expenseChange,
            totalExpense: totalExpense,
            totalIncome: totalIncome,
            period: period,
            target: target,
            selection: selection,
            transactions: currentExpenses,
            timeBuckets: timeBuckets,
            calculator: calculator
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
            smartAnalysis: smartAnalysis,
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

    private func buildSmartAnalysis(
        categoryBreakdown: [CategorySpending],
        expenseChange: Double?,
        totalExpense: Decimal,
        totalIncome: Decimal,
        period: ReportPeriod,
        target: ReportTarget,
        selection: ReportPeriodSelection,
        transactions: [Transaction],
        timeBuckets: [ReportTimeBucket],
        calculator: ReportPeriodCalculator
    ) -> ReportSmartAnalysis {
        var insights: [ReportInsight] = []
        let periodName = target.isCurrent ? period.currentTitle : "报告期内"
        let peakBucket = timeBuckets.max { lhs, rhs in lhs.expense < rhs.expense }
        let peakShare = peakBucket.map { bucket in
            totalExpense > 0
                ? NSDecimalNumber(decimal: bucket.expense / totalExpense).doubleValue
                : 0
        } ?? 0
        let activeBucketCount = timeBuckets.filter { $0.expense > 0 }.count
        let expenseCount = transactions.count
        let average = averageExpense(
            totalExpense: totalExpense,
            expenseCount: expenseCount,
            period: period,
            range: selection.reportRange
        )
        let projectedExpense = projectedExpense(
            totalExpense: totalExpense,
            period: period,
            target: target,
            selection: selection,
            calculator: calculator
        )
        let savingsRate = totalIncome > 0
            ? NSDecimalNumber(decimal: (totalIncome - totalExpense) / totalIncome).doubleValue
            : nil

        if let peakBucket, peakBucket.expense > 0 {
            insights.append(ReportInsight(
                id: "period-peak",
                title: peakInsightTitle(period: period),
                detail: "\(peakBucket.label)支出 \(peakBucket.expense.formattedCurrency)，占本期支出的 \(ReportPercentageFormatter.categoryShare(peakShare))。",
                systemImage: peakInsightIcon(period: period),
                tone: peakShare >= 0.5 ? .attention : .neutral,
                isSensitive: false
            ))
        }

        if let top = categoryBreakdown.first {
            let percentage = ReportPercentageFormatter.categoryShare(top.percentage)
            insights.append(ReportInsight(
                id: "category-concentration",
                title: top.percentage > 0.4 ? "消费集中度偏高" : "主要消费去向",
                detail: "\(periodName)\(top.categoryName)占比最高，达 \(percentage)\(top.percentage > 0.4 ? "，可优先检查这一类支出" : "")。",
                systemImage: "chart.pie.fill",
                tone: top.percentage > 0.4 ? .attention : .neutral,
                isSensitive: false
            ))
        }

        if let change = expenseChange {
            let percentage = ReportPercentageFormatter.changeRate(change)
            if change > 0.1 {
                insights.append(ReportInsight(
                    id: "expense-trend",
                    title: "支出节奏加快",
                    detail: "\(periodName)总支出比上期同期增加 \(percentage)。",
                    systemImage: "arrow.up.right",
                    tone: .attention,
                    isSensitive: false
                ))
            } else if change < -0.1 {
                insights.append(ReportInsight(
                    id: "expense-trend",
                    title: "支出有所回落",
                    detail: "\(periodName)总支出比上期同期减少 \(percentage)，消费节奏更稳健。",
                    systemImage: "arrow.down.right",
                    tone: .positive,
                    isSensitive: false
                ))
            } else {
                insights.append(ReportInsight(
                    id: "expense-trend",
                    title: "支出保持平稳",
                    detail: "\(periodName)总支出与上期同期基本持平。",
                    systemImage: "equal.circle.fill",
                    tone: .neutral,
                    isSensitive: false
                ))
            }
        }

        if let fastestChangingCategory = categoryBreakdown
            .prefix(5)
            .compactMap({ category -> (CategorySpending, Double)? in
                guard let change = category.changeFromLastPeriod, abs(change) > 0.2 else { return nil }
                return (category, change)
            })
            .max(by: { abs($0.1) < abs($1.1) }) {
            let category = fastestChangingCategory.0
            let change = fastestChangingCategory.1
            insights.append(ReportInsight(
                id: "category-shift",
                title: "分类变化值得关注",
                detail: "\(category.categoryName)比上期\(change > 0 ? "增加" : "减少") \(ReportPercentageFormatter.changeRate(change))。",
                systemImage: "arrow.triangle.2.circlepath",
                tone: change > 0 ? .attention : .positive,
                isSensitive: false
            ))
        }

        let amounts = transactions.map(\.amount).sorted()
        if amounts.count >= 4 {
            let median = amounts[amounts.count / 2]
            if let unusual = transactions.max(by: { $0.amount < $1.amount }),
               median > 0,
               unusual.amount >= median * 3 {
                let name = unusual.category?.reportDisplayName ?? "未分类"
                insights.append(ReportInsight(
                    id: "unusual-transaction",
                    title: "发现异常大额支出",
                    detail: "一笔 \(name) 支出为 \(unusual.amount.formattedCurrency)，达到本期支出中位数的 3 倍以上。",
                    systemImage: "exclamationmark.magnifyingglass",
                    tone: .attention,
                    isSensitive: false
                ))
            }
        }

        if period != .daily, !transactions.isEmpty {
            let weekendExpense = sum(transactions.filter { calendar.isDateInWeekend($0.date) })
            let weekendShare = totalExpense > 0
                ? NSDecimalNumber(decimal: weekendExpense / totalExpense).doubleValue
                : 0
            if weekendShare >= 0.45 {
                insights.append(ReportInsight(
                    id: "weekend-share",
                    title: "周末消费较集中",
                    detail: "周末支出占本期 \(ReportPercentageFormatter.categoryShare(weekendShare))，可留意休闲与临时消费。",
                    systemImage: "calendar.badge.exclamationmark",
                    tone: .attention,
                    isSensitive: false
                ))
            }
        }

        if let projectedExpense, period != .daily {
            insights.append(ReportInsight(
                id: "expense-projection",
                title: projectionTitle(period: period),
                detail: "按当前平均节奏，预计本期支出约为 \(projectedExpense.formattedCurrency)。预测会随新记录动态调整。",
                systemImage: "scope",
                tone: .neutral,
                isSensitive: false
            ))
        }

        if let savingsRate {
            let isHealthy = savingsRate >= 0.2
            insights.append(ReportInsight(
                id: "savings-rate",
                title: savingsRate >= 0 ? "本期结余率" : "本期支出超过收入",
                detail: savingsRate >= 0
                    ? "收入中有 \(ReportPercentageFormatter.categoryShare(savingsRate)) 转化为结余\(isHealthy ? "，安全边际较充足" : "。")"
                    : "支出相当于收入的 \(unboundedPercentage(1 - savingsRate))，建议优先检查大额与高增长分类。",
                systemImage: savingsRate >= 0 ? "shield.checkered" : "exclamationmark.shield.fill",
                tone: isHealthy ? .positive : (savingsRate < 0 ? .attention : .neutral),
                isSensitive: true
            ))
        }

        return ReportSmartAnalysis(
            averageExpense: average.amount,
            averageLabel: average.label,
            averageDetail: average.detail,
            peakBucket: peakBucket?.expense == 0 ? nil : peakBucket,
            peakShare: peakShare,
            activeBucketCount: activeBucketCount,
            activeBucketLabel: activeBucketLabel(period: period),
            projectedExpense: projectedExpense,
            savingsRate: savingsRate,
            insights: insights
        )
    }

    private func averageExpense(
        totalExpense: Decimal,
        expenseCount: Int,
        period: ReportPeriod,
        range: ReportDateRange
    ) -> (amount: Decimal, label: String, detail: String) {
        if period == .daily {
            let divisor = max(expenseCount, 1)
            return (totalExpense / Decimal(divisor), "笔均支出", "共 \(expenseCount) 笔支出")
        }

        let component: Calendar.Component = period == .yearly ? .month : .day
        let value = calendar.dateComponents([component], from: range.start, to: range.end).value(for: component) ?? 0
        let includesPartialUnit: Bool
        if period == .yearly {
            includesPartialUnit = calendar.component(.day, from: range.end) != 1
                || calendar.component(.hour, from: range.end) != 0
                || calendar.component(.minute, from: range.end) != 0
        } else {
            includesPartialUnit = range.end != calendar.startOfDay(for: range.end)
        }
        let elapsedUnits = max(value + (includesPartialUnit ? 1 : 0), 1)
        let unit = period == .yearly ? "月" : "天"
        return (totalExpense / Decimal(elapsedUnits), "\(unit)均支出", "按已覆盖 \(elapsedUnits) \(unit)计算")
    }

    private func projectedExpense(
        totalExpense: Decimal,
        period: ReportPeriod,
        target: ReportTarget,
        selection: ReportPeriodSelection,
        calculator: ReportPeriodCalculator
    ) -> Decimal? {
        guard target.isCurrent, totalExpense > 0 else { return nil }
        let fullEnd = calculator.currentPeriodEnd(for: period, referenceDate: target.referenceDate)
        let elapsed = selection.reportRange.end.timeIntervalSince(selection.reportRange.start)
        let fullDuration = fullEnd.timeIntervalSince(selection.reportRange.start)
        guard fullDuration > 0 else { return nil }
        let progress = min(max(elapsed / fullDuration, 0), 1)
        let minimumProgress = period == .daily ? 0.25 : 0.15
        guard progress >= minimumProgress, progress < 0.98 else { return nil }
        return totalExpense / Decimal(progress)
    }

    private func peakInsightTitle(period: ReportPeriod) -> String {
        switch period {
        case .daily: return "今日高峰时段"
        case .weekly: return "本周支出峰值日"
        case .monthly: return "本月支出峰值周"
        case .yearly: return "本年支出峰值月"
        case .payCycle: return "本周期支出峰值日"
        }
    }

    private func peakInsightIcon(period: ReportPeriod) -> String {
        period == .daily ? "clock.fill" : "chart.bar.fill"
    }

    private func activeBucketLabel(period: ReportPeriod) -> String {
        switch period.bucketGranularity {
        case .hour: return "活跃时段"
        case .day: return "消费天数"
        case .week: return "活跃周数"
        case .month: return "活跃月份"
        }
    }

    private func projectionTitle(period: ReportPeriod) -> String {
        switch period {
        case .weekly: return "本周支出预测"
        case .monthly: return "本月支出预测"
        case .yearly: return "本年支出预测"
        case .payCycle: return "本周期支出预测"
        case .daily: return "今日支出预测"
        }
    }

    private func unboundedPercentage(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if value >= 10 { return "999%+" }
        return "\(Int((max(value, 0) * 100).rounded()))%"
    }
}
