import Foundation
import SwiftData

/// 报表计算所需的最小交易值快照。它不携带 SwiftData 模型关系，可以安全地
/// 在数据 actor 和计算 actor 之间传递。
struct ReportTransactionSnapshot: Equatable, Sendable {
    let amount: Decimal
    let isExpense: Bool
    let date: Date
    let categoryName: String?
    let categoryIcon: String?
    let categoryColor: String?
    let isProtectedIncome: Bool
    let isIncludedInDailyBudget: Bool

    init(
        amount: Decimal,
        isExpense: Bool,
        date: Date,
        categoryName: String?,
        categoryIcon: String?,
        categoryColor: String?,
        isProtectedIncome: Bool,
        isIncludedInDailyBudget: Bool
    ) {
        self.amount = amount
        self.isExpense = isExpense
        self.date = date
        self.categoryName = categoryName
        self.categoryIcon = categoryIcon
        self.categoryColor = categoryColor
        self.isProtectedIncome = isProtectedIncome
        self.isIncludedInDailyBudget = isIncludedInDailyBudget
    }

    init(transaction: Transaction) {
        self.init(
            amount: transaction.amount,
            isExpense: transaction.isExpense,
            date: transaction.date,
            categoryName: transaction.category?.reportDisplayName,
            categoryIcon: transaction.category?.reportIcon,
            categoryColor: transaction.category?.reportColorHex,
            isProtectedIncome: transaction.isProtectedIncome,
            isIncludedInDailyBudget: BudgetScope.includesInDailyBudget(transaction)
        )
    }
}

struct ReportBudgetInputSnapshot: Equatable, Sendable {
    let id: UUID
    let monthlyLimit: Decimal
    let year: Int
    let month: Int
    let createdAt: Date
    let ledgerID: UUID?
    let categoryID: UUID?

    init(
        id: UUID,
        monthlyLimit: Decimal,
        year: Int,
        month: Int,
        createdAt: Date,
        ledgerID: UUID?,
        categoryID: UUID?
    ) {
        self.id = id
        self.monthlyLimit = monthlyLimit
        self.year = year
        self.month = month
        self.createdAt = createdAt
        self.ledgerID = ledgerID
        self.categoryID = categoryID
    }

    init(budget: Budget) {
        self.init(
            id: budget.id,
            monthlyLimit: budget.monthlyLimit,
            year: budget.year,
            month: budget.month,
            createdAt: budget.createdAt,
            ledgerID: budget.ledger?.id,
            categoryID: budget.categoryId
        )
    }
}

struct ReportDataSnapshot: Sendable {
    let currentTransactions: [ReportTransactionSnapshot]
    let comparisonTransactions: [ReportTransactionSnapshot]
    /// 有记账记录的自然日（当天起始时刻）。至少覆盖整个报告期，并沿连续链
    /// 向更早延伸到断点为止——足够算连续天数，又不必物化全部历史交易。
    let loggedDays: Set<Date>
    let budgetTransactions: [ReportTransactionSnapshot]
    let budgets: [ReportBudgetInputSnapshot]
}

/// 在独立 ModelContext 中读取报表输入，避免界面 context 被长时间聚合占用。
@ModelActor
actor LocalAnalyticsDataStore {
    /// 打卡日回溯的分块大小与最大块数（90 天 × 40 ≈ 10 年）。
    /// 连续链一断就提前收尾，块数上限只是异常数据下的兜底。
    private static let loggedDayChunkSize = 90
    private static let maxLoggedDayChunks = 40

    func makeSnapshot(
        period: ReportPeriod,
        target: ReportTarget,
        payday: Int,
        calendar: Calendar = .current
    ) throws -> ReportDataSnapshot {
        let periodCalculator = ReportPeriodCalculator(calendar: calendar, payday: payday)
        let selection = periodCalculator.selection(for: period, target: target)
        let current = try fetchTransactions(in: selection.reportRange)
        let comparison = try fetchTransactions(in: selection.comparisonRange)
        let loggedDays = try fetchLoggedDays(
            coveringFrom: selection.reportRange.start,
            endingBefore: selection.reportRange.end,
            calendar: calendar
        )

        let budgetAnchor = target.isCurrent
            ? selection.reportRange.end
            : ReportDateRangeFormatter(calendar: calendar).inclusiveEndDate(for: selection.reportRange)
        let cycle = PayCycleService.cycle(containing: budgetAnchor, payday: payday, calendar: calendar)
        let cutoff = min(cycle.end, selection.reportRange.end)
        let budgetRange = ReportDateRange(start: cycle.start, end: max(cycle.start, cutoff))
        let budgetTransactions = try fetchTransactions(in: budgetRange)
        let budgets = try modelContext.fetch(FetchDescriptor<Budget>())

        return ReportDataSnapshot(
            currentTransactions: current.map(ReportTransactionSnapshot.init(transaction:)),
            comparisonTransactions: comparison.map(ReportTransactionSnapshot.init(transaction:)),
            loggedDays: loggedDays,
            budgetTransactions: budgetTransactions.map(ReportTransactionSnapshot.init(transaction:)),
            budgets: budgets.map(ReportBudgetInputSnapshot.init(budget:))
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

    /// 从报告期结束向前分块回溯打卡日，连续链一断就停。
    /// 早前的实现没有时间下界，为了算连续天数会把用户全部历史交易读进内存，
    /// 而且那份数据是其它三次取数的超集，等于同一批记录重复物化多次。
    private func fetchLoggedDays(
        coveringFrom rangeStart: Date,
        endingBefore end: Date,
        calendar: Calendar
    ) throws -> Set<Date> {
        var days: Set<Date> = []
        var cursor = end

        for _ in 0..<Self.maxLoggedDayChunks {
            // 块边界必须对齐到自然日零点：否则跨块的那一天会被切成两半，
            // 接缝处看起来「没有记录」，凭空制造出一个断点。
            guard let rawStart = calendar.date(
                byAdding: .day,
                value: -Self.loggedDayChunkSize,
                to: cursor
            ) else { break }
            let chunkStart = calendar.startOfDay(for: rawStart)
            guard chunkStart < cursor else { break }

            let chunk = try fetchTransactions(in: ReportDateRange(start: chunkStart, end: cursor))
            days.formUnion(chunk.map { calendar.startOfDay(for: $0.date) })
            cursor = chunkStart

            // 热力图需要完整的报告期，连续天数需要扫到断点为止——两个条件都满足才收工。
            let coversReportRange = cursor <= rangeStart
            let streakMayExtendEarlier = ReportStreakCalculator.extendsBefore(
                cursor,
                endingBefore: end,
                loggedDays: days,
                calendar: calendar
            )
            if coversReportRange, !streakMayExtendEarlier { break }
        }

        return days
    }
}

/// 非主线程执行的纯报表聚合器。
struct ReportCalculator {
    private let calendar: Calendar
    private let payday: Int

    init(calendar: Calendar = .current, payday: Int = 1) {
        self.calendar = calendar
        self.payday = min(max(payday, 1), 31)
    }

    func generateReport(
        period: ReportPeriod,
        target: ReportTarget,
        snapshot: ReportDataSnapshot,
        includePrivateIncome: Bool = true
    ) -> ReportData {
        let calculator = ReportPeriodCalculator(calendar: calendar, payday: payday)
        let selection = calculator.selection(for: period, target: target)
        let currentTransactions = snapshot.currentTransactions
        let comparisonTransactions = snapshot.comparisonTransactions
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
            total: totalExpense,
            previousTransactions: comparisonExpenses
        )
        let incomeBreakdown = buildCategoryBreakdown(
            transactions: currentIncome,
            total: totalIncome,
            previousTransactions: comparisonIncome
        )
        let timeBuckets = buildTimeBuckets(
            transactions: currentExpenses,
            selection: selection,
            calculator: calculator
        )
        let streakDays = ReportStreakCalculator.streak(
            endingBefore: selection.reportRange.end,
            loggedDays: snapshot.loggedDays,
            calendar: calendar
        )
        let loggingDays = buildLoggingDays(
            endingBefore: selection.reportRange.end,
            loggedDays: snapshot.loggedDays
        )
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
            incomeBreakdown: incomeBreakdown,
            timeBuckets: timeBuckets,
            streakDays: streakDays,
            loggingDays: loggingDays,
            smartAnalysis: smartAnalysis,
            transactionCount: currentTransactions.count
        )
    }

    private func visibleIncome(
        in transactions: [ReportTransactionSnapshot],
        includePrivateIncome: Bool
    ) -> [ReportTransactionSnapshot] {
        transactions.filter { !$0.isExpense && (includePrivateIncome || !$0.isProtectedIncome) }
    }

    private func sum(_ transactions: [ReportTransactionSnapshot]) -> Decimal {
        transactions.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private func percentageChange(current: Decimal, previous: Decimal) -> Double? {
        guard previous > 0 else { return nil }
        return NSDecimalNumber(decimal: (current - previous) / previous).doubleValue
    }

    private func buildCategoryBreakdown(
        transactions: [ReportTransactionSnapshot],
        total: Decimal,
        previousTransactions: [ReportTransactionSnapshot]
    ) -> [CategorySpending] {
        let grouped = Dictionary(grouping: transactions) { $0.categoryName ?? "未分类" }
        let previousGrouped = Dictionary(grouping: previousTransactions) { $0.categoryName ?? "未分类" }

        return grouped.map { name, transactions in
            let amount = sum(transactions)
            let previousAmount = sum(previousGrouped[name] ?? [])
            let firstTransaction = transactions.first
            return CategorySpending(
                categoryName: name,
                categoryIcon: firstTransaction?.categoryIcon ?? "questionmark",
                categoryColor: firstTransaction?.categoryColor ?? "#667EEA",
                amount: amount,
                percentage: total > 0
                    ? NSDecimalNumber(decimal: amount / total).doubleValue
                    : 0,
                changeFromLastPeriod: percentageChange(current: amount, previous: previousAmount)
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    private func buildTimeBuckets(
        transactions: [ReportTransactionSnapshot],
        selection: ReportPeriodSelection,
        calculator: ReportPeriodCalculator
    ) -> [ReportTimeBucket] {
        let ranges = calculator.bucketRanges(for: selection)
        guard !ranges.isEmpty else { return [] }

        // 桶按时间升序且互不重叠，二分定位即可。
        // 逐桶 filter 全量交易会退化成 O(桶数 × 交易数)——年报是 12 遍，日报是 24 遍。
        var totals = [Decimal](repeating: 0, count: ranges.count)
        for transaction in transactions {
            guard let index = bucketIndex(for: transaction.date, in: ranges) else { continue }
            totals[index] += transaction.amount
        }

        let granularity = selection.period.bucketGranularity
        let formatter = ReportDateRangeFormatter(calendar: calendar)
        return ranges.enumerated().map { index, range in
            ReportTimeBucket(
                range: range,
                granularity: granularity,
                label: formatter.bucketLabel(for: range, granularity: granularity),
                expense: totals[index]
            )
        }
    }

    /// 打卡网格固定取最近 5 周（7 列 × 5 行）。
    /// 年报若逐日铺开会有 365 格，既排不下也读不出信息。
    private static let loggingGridDayCount = 35

    private func buildLoggingDays(
        endingBefore end: Date,
        loggedDays: Set<Date>
    ) -> [ReportLoggingDay] {
        let reference = ReportStreakCalculator.referenceDay(endingBefore: end, calendar: calendar)
        return (0..<Self.loggingGridDayCount).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: reference) else { return nil }
            return ReportLoggingDay(date: day, isLogged: loggedDays.contains(day))
        }
    }

    private func bucketIndex(for date: Date, in ranges: [ReportDateRange]) -> Int? {
        var low = 0
        var high = ranges.count - 1
        while low <= high {
            let mid = low + (high - low) / 2
            if date < ranges[mid].start {
                high = mid - 1
            } else if date >= ranges[mid].end {
                low = mid + 1
            } else {
                return mid
            }
        }
        return nil
    }

    private func buildSmartAnalysis(
        categoryBreakdown: [CategorySpending],
        expenseChange: Double?,
        totalExpense: Decimal,
        totalIncome: Decimal,
        period: ReportPeriod,
        target: ReportTarget,
        selection: ReportPeriodSelection,
        transactions: [ReportTransactionSnapshot],
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
        let average = averageExpense(
            totalExpense: totalExpense,
            expenseCount: transactions.count,
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
            let title: String
            let detail: String
            let tone: ReportInsightTone
            if change > 0.1 {
                title = "支出节奏加快"
                detail = "\(periodName)总支出比上期同期增加 \(percentage)。"
                tone = .attention
            } else if change < -0.1 {
                title = "支出有所回落"
                detail = "\(periodName)总支出比上期同期减少 \(percentage)，消费节奏更稳健。"
                tone = .positive
            } else {
                title = "支出保持平稳"
                detail = "\(periodName)总支出与上期同期基本持平。"
                tone = .neutral
            }
            insights.append(ReportInsight(
                id: "expense-trend",
                title: title,
                detail: detail,
                systemImage: change > 0.1 ? "arrow.up.right" : (change < -0.1 ? "arrow.down.right" : "equal.circle.fill"),
                tone: tone,
                isSensitive: false
            ))
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
        if amounts.count >= 4,
           let unusual = transactions.max(by: { $0.amount < $1.amount }) {
            let median = amounts[amounts.count / 2]
            if median > 0, unusual.amount >= median * 3 {
                let name = unusual.categoryName ?? "未分类"
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

actor ReportComputationWorker {
    func calculatePage(
        period: ReportPeriod,
        target: ReportTarget,
        payday: Int,
        calendar: Calendar,
        snapshot: ReportDataSnapshot,
        weekendMultiplier: Decimal
    ) -> ReportPageCalculation {
        let report = ReportCalculator(calendar: calendar, payday: payday).generateReport(
            period: period,
            target: target,
            snapshot: snapshot,
            includePrivateIncome: true
        )
        let budget = ReportBudgetSnapshotService.snapshotValue(
            budgets: snapshot.budgets,
            transactions: snapshot.budgetTransactions,
            reportRange: report.reportRange,
            target: target,
            payday: payday,
            calendar: calendar,
            weekendMultiplier: weekendMultiplier
        )
        return ReportPageCalculation(report: report, budget: budget)
    }

    func calculate(
        period: ReportPeriod,
        target: ReportTarget,
        payday: Int,
        calendar: Calendar,
        snapshot: ReportDataSnapshot
    ) -> ReportData {
        ReportCalculator(calendar: calendar, payday: payday).generateReport(
            period: period,
            target: target,
            snapshot: snapshot,
            includePrivateIncome: true
        )
    }
}

struct ReportPageCalculation: Sendable {
    let report: ReportData
    let budget: ReportBudgetSnapshotValue
}
