import Foundation

/// 预算分析结果
struct BudgetAnalysis {
    let budgetLimit: Decimal         // 预算上限
    let totalSpent: Decimal          // 已花费
    let daysElapsed: Int             // 已过天数
    let daysRemaining: Int           // 剩余天数
    let totalDaysInMonth: Int        // 当月总天数
    let dailyAverage: Decimal        // 日均消费
    let projectedTotal: Decimal      // 预测月底总消费
    let remainingBudget: Decimal     // 剩余预算
    let dailyAllowance: Decimal      // 每日可花
    let usagePercent: Double         // 已用百分比
    let alertLevel: BudgetAlertLevel // 预警等级

    /// 友好的预警消息
    var alertMessage: String {
        switch alertLevel {
        case .healthy:
            return "预算充裕，继续保持 💪"
        case .warning:
            let remaining = remainingBudget as NSDecimalNumber
            return "注意控制开支！剩余 ¥\(remaining.intValue)，日均可花 ¥\((dailyAllowance as NSDecimalNumber).intValue)"
        case .danger:
            if projectedTotal > budgetLimit {
                let overAmount = (projectedTotal - budgetLimit) as NSDecimalNumber
                return "🚨 按目前进度，月底将超支 ¥\(overAmount.intValue)！你要吃土了！"
            }
            return "🚨 预算已用完，请控制开支！"
        }
    }
}

/// 预算分析器
struct BudgetAnalyzer {

    /// 分析当月预算消费情况
    /// - Parameters:
    ///   - budgetLimit: 月度预算上限
    ///   - totalSpent: 当月已消费总额（正数）
    ///   - referenceDate: 参考日期（默认今天）
    /// - Returns: 预算分析结果
    static func analyze(
        budgetLimit: Decimal,
        totalSpent: Decimal,
        referenceDate: Date = Date()
    ) -> BudgetAnalysis {
        let calendar = Calendar.current

        // 计算当月天数信息
        let components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        let daysElapsed = max(components.day ?? 1, 1)  // 至少1天避免除零

        let range = calendar.range(of: .day, in: .month, for: referenceDate)!
        let totalDaysInMonth = range.count
        let daysRemaining = max(totalDaysInMonth - daysElapsed, 0)

        // 计算指标
        let dailyAverage = totalSpent / Decimal(daysElapsed)
        let projectedTotal = dailyAverage * Decimal(totalDaysInMonth)
        let remainingBudget = budgetLimit - totalSpent
        let dailyAllowance = daysRemaining > 0
            ? max(remainingBudget / Decimal(daysRemaining), 0)
            : 0

        // 使用百分比
        let usagePercent = budgetLimit > 0
            ? NSDecimalNumber(decimal: totalSpent / budgetLimit).doubleValue
            : 0

        // 预警等级（基于预测消费）
        let projectedPercent = budgetLimit > 0
            ? NSDecimalNumber(decimal: projectedTotal / budgetLimit).doubleValue
            : 0

        let alertLevel: BudgetAlertLevel
        if projectedPercent > 1.0 || usagePercent > 1.0 {
            alertLevel = .danger
        } else if projectedPercent > 0.8 {
            alertLevel = .warning
        } else {
            alertLevel = .healthy
        }

        return BudgetAnalysis(
            budgetLimit: budgetLimit,
            totalSpent: totalSpent,
            daysElapsed: daysElapsed,
            daysRemaining: daysRemaining,
            totalDaysInMonth: totalDaysInMonth,
            dailyAverage: dailyAverage,
            projectedTotal: projectedTotal,
            remainingBudget: remainingBudget,
            dailyAllowance: dailyAllowance,
            usagePercent: usagePercent,
            alertLevel: alertLevel
        )
    }
}
