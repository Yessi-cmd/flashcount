import Foundation

/// 预算分析结果
struct BudgetAnalysis {
    let budgetLimit: Decimal         // 预算上限
    let totalSpent: Decimal          // 预算内已花费
    let excludedSpent: Decimal       // 已记录但不计入预算的支出
    let daysElapsed: Int             // 已过天数
    let daysRemaining: Int           // 剩余天数
    let totalDaysInMonth: Int        // 当月总天数
    let periodStart: Date
    let periodEnd: Date
    let dailyAverage: Decimal        // 日均消费
    let projectedTotal: Decimal      // 预测月底总消费
    let remainingBudget: Decimal     // 剩余预算
    let dailyAllowance: Decimal      // 每日可花
    let referenceDateIsWeekend: Bool  // 参考日是否为周末
    let weekendMultiplier: Decimal    // 周末日额度权重
    let usagePercent: Double         // 已用百分比
    let alertLevel: BudgetAlertLevel // 预警等级

    var projectedBalance: Decimal {
        budgetLimit - projectedTotal
    }

    var projectedOverAmount: Decimal {
        max(projectedTotal - budgetLimit, 0)
    }

    /// 友好的预警消息
    var alertMessage: String {
        switch alertLevel {
        case .healthy:
            return "日常预算健康，今天建议不超过 \(dailyAllowance.formattedCurrency)"
        case .warning:
            return "注意消费节奏。剩余 \(daysRemaining) 天，今天建议不超过 \(dailyAllowance.formattedCurrency)"
        case .danger:
            if projectedOverAmount > 0 {
                return "按目前进度，月底预计超支 \(projectedOverAmount.formattedCurrency)"
            }
            return "日常预算已用完，请控制接下来的支出"
        }
    }

    var dailyAllowanceTitle: String {
        "今日可花"
    }

    var isWeekendAllowanceAdjusted: Bool {
        referenceDateIsWeekend && weekendMultiplier > 1
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
        excludedSpent: Decimal = 0,
        referenceDate: Date = Date(),
        periodStart: Date? = nil,
        periodEnd: Date? = nil,
        weekendMultiplier: Decimal = 1,
        calendar: Calendar = .current
    ) -> BudgetAnalysis {
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let defaultStart = calendar.dateInterval(of: .month, for: referenceDate)?.start ?? referenceDay
        let defaultEnd = calendar.dateInterval(of: .month, for: referenceDate)?.end
            ?? calendar.date(byAdding: .month, value: 1, to: defaultStart)
            ?? referenceDay
        let start = calendar.startOfDay(for: periodStart ?? defaultStart)
        let requestedEnd = calendar.startOfDay(for: periodEnd ?? defaultEnd)
        let end = max(requestedEnd, calendar.date(byAdding: .day, value: 1, to: start) ?? requestedEnd)

        let totalDaysInMonth = max(calendar.dateComponents([.day], from: start, to: end).day ?? 1, 1)
        let lastPeriodDay = calendar.date(byAdding: .day, value: -1, to: end) ?? start
        let elapsedDate = min(max(referenceDay, start), lastPeriodDay)
        let daysElapsed = max((calendar.dateComponents([.day], from: start, to: elapsedDate).day ?? 0) + 1, 1)
        let daysRemaining = max(calendar.dateComponents([.day], from: referenceDay, to: end).day ?? 0, 0)

        // 计算指标
        let dailyAverage = totalSpent / Decimal(daysElapsed)
        let projectedTotal = dailyAverage * Decimal(totalDaysInMonth)
        let remainingBudget = budgetLimit - totalSpent
        let normalizedWeekendMultiplier = max(weekendMultiplier, Decimal(1))
        let referenceDateIsWeekend = calendar.isDateInWeekend(referenceDay)

        // 用权重分配剩余预算：周末提高额度后，工作日自动回调，周期总额仍保持不变。
        let remainingWeight: Decimal
        if daysRemaining > 0 {
            var date = referenceDay
            var weight = Decimal(0)
            for _ in 0..<daysRemaining {
                weight += calendar.isDateInWeekend(date) ? normalizedWeekendMultiplier : Decimal(1)
                date = calendar.date(byAdding: .day, value: 1, to: date) ?? end
            }
            remainingWeight = weight
        } else {
            remainingWeight = 0
        }
        let todayWeight = referenceDateIsWeekend ? normalizedWeekendMultiplier : Decimal(1)
        let dailyAllowance = daysRemaining > 0 && remainingWeight > 0
            ? max(remainingBudget * todayWeight / remainingWeight, 0)
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
            excludedSpent: excludedSpent,
            daysElapsed: daysElapsed,
            daysRemaining: daysRemaining,
            totalDaysInMonth: totalDaysInMonth,
            periodStart: start,
            periodEnd: end,
            dailyAverage: dailyAverage,
            projectedTotal: projectedTotal,
            remainingBudget: remainingBudget,
            dailyAllowance: dailyAllowance,
            referenceDateIsWeekend: referenceDateIsWeekend,
            weekendMultiplier: normalizedWeekendMultiplier,
            usagePercent: usagePercent,
            alertLevel: alertLevel
        )
    }
}
