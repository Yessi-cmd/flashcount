import Foundation

/// 从最近的完整记录周提取可解释的日常消费节奏。
///
/// 区间是历史周支出的 P20 / P50 / P80，不声称为统计置信区间。整周没有
/// 任何交易时按「缺少记录」跳过；只要该周有记录，即使日常预算支出为零，
/// 也会把零纳入样本，避免只保留高消费周。
struct RoutineSpendingProfile: Equatable {
    enum DataBasis: Equatable {
        case unavailable
        case preliminary
        case limited
        case sufficient
    }

    let lighterWeeklyExpense: Decimal
    let typicalWeeklyExpense: Decimal
    let higherWeeklyExpense: Decimal
    let observedWeekCount: Int
    let qualifyingTransactionCount: Int
    let weeklyTotals: [Decimal]
    let dataBasis: DataBasis

    var lighterDailyExpense: Decimal {
        lighterWeeklyExpense / Decimal(7)
    }

    var typicalDailyExpense: Decimal {
        typicalWeeklyExpense / Decimal(7)
    }

    var higherDailyExpense: Decimal {
        higherWeeklyExpense / Decimal(7)
    }

    var supportsRange: Bool {
        dataBasis == .limited || dataBasis == .sufficient
    }

    var hasVisibleSpread: Bool {
        supportsRange && higherDailyExpense > lighterDailyExpense
    }

    static func calculate(
        transactions: [Transaction],
        referenceDate: Date,
        calendar: Calendar,
        lookbackDays: Int
    ) -> RoutineSpendingProfile? {
        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2
        weekCalendar.minimumDaysInFirstWeek = 4

        let referenceDay = weekCalendar.startOfDay(for: referenceDate)
        guard let currentWeekStart = weekCalendar.dateInterval(
            of: .weekOfYear,
            for: referenceDay
        )?.start else {
            return nil
        }

        let maximumWeekCount = max(lookbackDays / 7, 1)
        guard let historyStart = weekCalendar.date(
            byAdding: .weekOfYear,
            value: -maximumWeekCount,
            to: currentWeekStart
        ) else {
            return nil
        }

        var weeklyTotals: [Decimal] = []
        var qualifyingTransactionCount = 0
        var weekStart = historyStart

        while weekStart < currentWeekStart {
            guard let weekEnd = weekCalendar.date(
                byAdding: .weekOfYear,
                value: 1,
                to: weekStart
            ), weekEnd > weekStart else {
                break
            }

            let weekTransactions = transactions.filter {
                $0.date >= weekStart && $0.date < weekEnd
            }
            if !weekTransactions.isEmpty {
                let routineTransactions = weekTransactions.filter {
                    $0.isExpense
                        && $0.recurringRule == nil
                        && BudgetScope.includesInDailyBudget($0)
                }
                weeklyTotals.append(
                    routineTransactions.reduce(Decimal.zero) { $0 + $1.amount }
                )
                qualifyingTransactionCount += routineTransactions.count
            }
            weekStart = weekEnd
        }

        guard !weeklyTotals.isEmpty else { return nil }

        let sortedTotals = weeklyTotals.sorted()
        let observedWeekCount = sortedTotals.count
        let dataBasis: DataBasis
        switch observedWeekCount {
        case 0:
            dataBasis = .unavailable
        case 1...3:
            dataBasis = .preliminary
        case 4...7:
            dataBasis = .limited
        default:
            dataBasis = .sufficient
        }

        let typicalWeeklyExpense = percentile(
            Decimal(1) / Decimal(2),
            in: sortedTotals
        )
        let lighterWeeklyExpense: Decimal
        let higherWeeklyExpense: Decimal
        if dataBasis == .limited || dataBasis == .sufficient {
            lighterWeeklyExpense = percentile(
                Decimal(1) / Decimal(5),
                in: sortedTotals
            )
            higherWeeklyExpense = percentile(
                Decimal(4) / Decimal(5),
                in: sortedTotals
            )
        } else {
            lighterWeeklyExpense = typicalWeeklyExpense
            higherWeeklyExpense = typicalWeeklyExpense
        }

        return RoutineSpendingProfile(
            lighterWeeklyExpense: lighterWeeklyExpense,
            typicalWeeklyExpense: typicalWeeklyExpense,
            higherWeeklyExpense: higherWeeklyExpense,
            observedWeekCount: observedWeekCount,
            qualifyingTransactionCount: qualifyingTransactionCount,
            weeklyTotals: weeklyTotals,
            dataBasis: dataBasis
        )
    }

    /// 线性插值分位数；全程使用 Decimal，避免把钱转成浮点数再参与计算。
    private static func percentile(
        _ percentile: Decimal,
        in sortedValues: [Decimal]
    ) -> Decimal {
        guard let first = sortedValues.first else { return 0 }
        guard sortedValues.count > 1 else { return first }

        let position = percentile * Decimal(sortedValues.count - 1)
        var lowerPosition = Decimal.zero
        var positionCopy = position
        NSDecimalRound(&lowerPosition, &positionCopy, 0, .down)

        let lowerIndex = NSDecimalNumber(decimal: lowerPosition).intValue
        let upperIndex = min(lowerIndex + 1, sortedValues.count - 1)
        let fraction = position - lowerPosition
        let lowerValue = sortedValues[lowerIndex]
        let upperValue = sortedValues[upperIndex]
        return lowerValue + (upperValue - lowerValue) * fraction
    }
}
