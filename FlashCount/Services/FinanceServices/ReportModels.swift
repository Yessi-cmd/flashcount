import Foundation

/// 分类消费汇总
struct CategorySpending: Identifiable {
    var id: String { categoryName }
    let categoryName: String
    let categoryIcon: String
    let categoryColor: String
    let amount: Decimal
    let percentage: Double
    let changeFromLastPeriod: Double?
    /// 饼图里把长尾合并成的「其他」。它没有对应的真实分类，
    /// 因此既不能下钻，也不该显示环比（`changeFromLastPeriod` 恒为 nil）。
    let isAggregate: Bool

    init(
        categoryName: String,
        categoryIcon: String,
        categoryColor: String,
        amount: Decimal,
        percentage: Double,
        changeFromLastPeriod: Double?,
        isAggregate: Bool = false
    ) {
        self.categoryName = categoryName
        self.categoryIcon = categoryIcon
        self.categoryColor = categoryColor
        self.amount = amount
        self.percentage = percentage
        self.changeFromLastPeriod = changeFromLastPeriod
        self.isAggregate = isAggregate
    }
}

/// 洞察条目的语气，决定配色与图标。区分「提醒注意」和「值得肯定」，
/// 全部一个颜色会让用户分不清哪条需要行动。
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

/// 打卡网格里的一天。
struct ReportLoggingDay: Identifiable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let isLogged: Bool
}

/// 报表数据。由 `ReportCalculator` 在后台 actor 上生成，界面只做展示。
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
    /// 收入的分类构成。界面必须在隐私锁开启时整体遮挡——
    /// 金额之外，分类名本身（「工资」「奖金」）同样是敏感信息。
    let incomeBreakdown: [CategorySpending]
    let timeBuckets: [ReportTimeBucket]
    let streakDays: Int
    /// 打卡热力网格：截至报告期末的最近若干天，每天是否有记录。
    let loggingDays: [ReportLoggingDay]
    let smartAnalysis: ReportSmartAnalysis
    let transactionCount: Int
}
