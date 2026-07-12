import Foundation
import SwiftData

/// 分类消费汇总
struct CategorySpending: Identifiable {
    let id = UUID()
    let categoryName: String
    let categoryIcon: String
    let categoryColor: String
    let amount: Decimal
    let percentage: Double // 0 ~ 1
    let changeFromLastPeriod: Double? // 比上期变化 (-0.2 = 减少20%)
}

/// 报表周期
enum ReportPeriod: String, CaseIterable {
    case weekly = "周报"
    case monthly = "月报"
}

/// 报表数据
struct ReportData {
    let period: ReportPeriod
    let totalExpense: Decimal
    let totalIncome: Decimal
    let netChange: Decimal
    let expenseChange: Double?     // 比上一期变化
    let incomeChange: Double?
    let hasHiddenPrivateIncome: Bool
    let categoryBreakdown: [CategorySpending]
    let dailyExpenses: [(String, Decimal)]  // (日期标签, 金额)
    let streakDays: Int           // 连续记账天数
    let insights: [String]        // 消费洞察
}

/// 报表服务
@MainActor
final class ReportService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// 生成报表
    func generateReport(period: ReportPeriod, includePrivateIncome: Bool = true) throws -> ReportData {
        let calendar = Calendar.current
        let now = Date()

        // 计算当前周期和上一周期的日期范围
        let (currentStart, currentEnd, previousStart, previousEnd) = dateRanges(for: period, from: now, calendar: calendar)

        // 获取交易
        let currentTransactions = try fetchTransactions(from: currentStart, to: currentEnd)
        let previousTransactions = try fetchTransactions(from: previousStart, to: previousEnd)
        let hasHiddenPrivateIncome = !includePrivateIncome && currentTransactions.contains { $0.isProtectedIncome }
        let incomeTransactions = currentTransactions.filter { !$0.isExpense && (includePrivateIncome || !$0.isProtectedIncome) }
        let previousIncomeTransactions = previousTransactions.filter { !$0.isExpense && (includePrivateIncome || !$0.isProtectedIncome) }

        // 基础统计
        let totalExpense = currentTransactions.filter { $0.isExpense }.reduce(Decimal(0)) { $0 + $1.amount }
        let totalIncome = incomeTransactions.reduce(Decimal(0)) { $0 + $1.amount }
        let prevExpense = previousTransactions.filter { $0.isExpense }.reduce(Decimal(0)) { $0 + $1.amount }
        let prevIncome = previousIncomeTransactions.reduce(Decimal(0)) { $0 + $1.amount }

        let expenseChange: Double? = prevExpense > 0 ? NSDecimalNumber(decimal: (totalExpense - prevExpense) / prevExpense).doubleValue : nil
        let incomeChange: Double? = prevIncome > 0 ? NSDecimalNumber(decimal: (totalIncome - prevIncome) / prevIncome).doubleValue : nil

        // 分类汇总
        let categoryBreakdown = buildCategoryBreakdown(
            transactions: currentTransactions.filter { $0.isExpense },
            totalExpense: totalExpense,
            previousTransactions: previousTransactions.filter { $0.isExpense }
        )

        // 每日消费
        let dailyExpenses = buildDailyExpenses(
            transactions: currentTransactions.filter { $0.isExpense },
            start: currentStart,
            end: min(currentEnd, now),
            period: period,
            calendar: calendar
        )

        // 连续记账天数
        let streakDays = try calculateStreak(calendar: calendar)

        // 消费洞察
        let insights = generateInsights(
            categoryBreakdown: categoryBreakdown,
            totalExpense: totalExpense,
            expenseChange: expenseChange,
            period: period,
            transactions: currentTransactions.filter(\.isExpense)
        )

        return ReportData(
            period: period,
            totalExpense: totalExpense,
            totalIncome: totalIncome,
            netChange: totalIncome - totalExpense,
            expenseChange: expenseChange,
            incomeChange: incomeChange,
            hasHiddenPrivateIncome: hasHiddenPrivateIncome,
            categoryBreakdown: categoryBreakdown,
            dailyExpenses: dailyExpenses,
            streakDays: streakDays,
            insights: insights
        )
    }

    // MARK: - Private

    private func dateRanges(for period: ReportPeriod, from date: Date, calendar: Calendar) -> (Date, Date, Date, Date) {
        switch period {
        case .weekly:
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date),
                  let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekInterval.start),
                  let prevStart = calendar.date(byAdding: .day, value: -7, to: weekInterval.start)
            else {
                let today = Date()
                return (today, today, today, today)
            }
            return (weekInterval.start, weekEnd, prevStart, weekInterval.start)
        case .monthly:
            guard let monthInterval = calendar.dateInterval(of: .month, for: date),
                  let prevMonthStart = calendar.date(byAdding: .month, value: -1, to: monthInterval.start)
            else {
                let today = Date()
                return (today, today, today, today)
            }
            return (monthInterval.start, monthInterval.end, prevMonthStart, monthInterval.start)
        }
    }

    private func fetchTransactions(from start: Date, to end: Date) throws -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { t in
                t.date >= start && t.date < end
            }
        )
        return try modelContext.fetch(descriptor)
    }

    private func buildCategoryBreakdown(transactions: [Transaction], totalExpense: Decimal, previousTransactions: [Transaction]) -> [CategorySpending] {
        let grouped = Dictionary(grouping: transactions) { $0.category?.reportDisplayName ?? "未分类" }
        let prevGrouped = Dictionary(grouping: previousTransactions) { $0.category?.reportDisplayName ?? "未分类" }

        return grouped.map { name, txns in
            let amount = txns.reduce(Decimal(0)) { $0 + $1.amount }
            let percentage = totalExpense > 0 ? NSDecimalNumber(decimal: amount / totalExpense).doubleValue : 0
            let prevAmount = prevGrouped[name]?.reduce(Decimal(0)) { $0 + $1.amount } ?? 0
            let change: Double? = prevAmount > 0 ? NSDecimalNumber(decimal: (amount - prevAmount) / prevAmount).doubleValue : nil
            let firstTxn = txns.first
            return CategorySpending(
                categoryName: name,
                categoryIcon: firstTxn?.category?.reportIcon ?? "questionmark",
                categoryColor: firstTxn?.category?.reportColorHex ?? "#667EEA",
                amount: amount,
                percentage: percentage,
                changeFromLastPeriod: change
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    private func buildDailyExpenses(transactions: [Transaction], start: Date, end: Date, period: ReportPeriod, calendar: Calendar) -> [(String, Decimal)] {
        var totalsByDay: [Date: Decimal] = [:]
        for transaction in transactions {
            let day = calendar.startOfDay(for: transaction.date)
            totalsByDay[day, default: 0] += transaction.amount
        }

        var result: [(String, Decimal)] = []
        var current = start
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = period == .weekly ? "E" : "d"

        while current < end {
            result.append((formatter.string(from: current), totalsByDay[current, default: 0]))
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return result
    }

    private func calculateStreak(calendar: Calendar) throws -> Int {
        let descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let transactions = try modelContext.fetch(descriptor)
        guard !transactions.isEmpty else { return 0 }

        let loggedDays = Set(transactions.map { calendar.startOfDay(for: $0.date) })
        var streak = 0
        let today = calendar.startOfDay(for: Date())
        var checkDate = loggedDays.contains(today)
            ? today
            : calendar.date(byAdding: .day, value: -1, to: today)!

        while loggedDays.contains(checkDate) {
            streak += 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        }
        return streak
    }

    private func generateInsights(categoryBreakdown: [CategorySpending], totalExpense: Decimal, expenseChange: Double?, period: ReportPeriod, transactions: [Transaction]) -> [String] {
        var insights: [String] = []
        let periodName = period == .weekly ? "本周" : "本月"

        // 最大消费分类
        if let top = categoryBreakdown.first {
            let pct = Int(top.percentage * 100)
            insights.append("\(periodName)\(top.categoryName)占比最高，达 \(pct)%")
            if pct > 40 {
                insights.append("\(top.categoryName)支出集中度偏高，建议适当控制")
            }
        }

        // 消费变化
        if let change = expenseChange {
            let pct = Int(abs(change) * 100)
            if change > 0.1 {
                insights.append("\(periodName)总支出比上期增加了 \(pct)%")
            } else if change < -0.1 {
                insights.append("\(periodName)总支出比上期减少了 \(pct)%，继续保持")
            } else {
                insights.append("\(periodName)总支出与上期基本持平")
            }
        }

        // 分类涨跌
        for cat in categoryBreakdown.prefix(3) {
            if let change = cat.changeFromLastPeriod, abs(change) > 0.2 {
                let pct = Int(abs(change) * 100)
                let arrow = change > 0 ? "↑" : "↓"
                insights.append("🔍 \(cat.categoryName) \(arrow) \(pct)%（对比上期）")
            }
        }

        let amounts = transactions.map(\.amount).sorted()
        if amounts.count >= 4 {
            let median = amounts[amounts.count / 2]
            if let unusual = transactions.max(by: { $0.amount < $1.amount }), median > 0, unusual.amount >= median * 3 {
                let name = unusual.category?.reportDisplayName ?? "未分类"
                insights.append("🔔 发现一笔较平时偏高的\(name)支出：\(unusual.amount.formattedCurrency)")
            }
        }

        return insights
    }
}
