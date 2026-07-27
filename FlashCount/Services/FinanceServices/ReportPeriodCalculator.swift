import Foundation

/// 支持的报表周期。
enum ReportPeriod: String, CaseIterable, Codable, Hashable, Sendable {
    case daily = "日报"
    case weekly = "周报"
    case monthly = "月报"
    case yearly = "年报"
    case payCycle = "周期报"

    var bucketGranularity: ReportTimeBucket.Granularity {
        switch self {
        case .daily: return .hour
        case .weekly, .payCycle: return .day
        case .monthly: return .week
        case .yearly: return .month
        }
    }

    var currentTitle: String {
        switch self {
        case .daily: return "今日"
        case .weekly: return "本周"
        case .monthly: return "本月"
        case .yearly: return "本年"
        case .payCycle: return "本周期"
        }
    }

    var accessibilityKey: String {
        switch self {
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .monthly: return "monthly"
        case .yearly: return "yearly"
        case .payCycle: return "payCycle"
        }
    }

    var chartTitle: String {
        switch bucketGranularity {
        case .hour: return "每小时支出"
        case .day: return "每日支出"
        case .week: return "每周支出"
        case .month: return "每月支出"
        }
    }
}

/// 报表所针对的时间。当前周期用于实时预览，完整周期用于历史浏览，定时目标用于通知。
enum ReportTarget: Equatable, Sendable {
    case current(referenceDate: Date)
    case completed(containing: Date)
    case scheduled(triggerDate: Date)

    var referenceDate: Date {
        switch self {
        case .current(let date), .completed(let date), .scheduled(let date): return date
        }
    }

    var isCurrent: Bool {
        if case .current = self { return true }
        return false
    }

    var isScheduled: Bool {
        if case .scheduled = self { return true }
        return false
    }

    static func scheduled(period: ReportPeriod, triggerDate: Date) -> ReportTarget {
        .scheduled(triggerDate: triggerDate)
    }
}

/// 所有区间均采用 [start, end) 语义。
struct ReportDateRange: Equatable, Sendable {
    let start: Date
    let end: Date

    init(start: Date, end: Date) {
        precondition(start <= end, "报表区间结束时间不能早于开始时间")
        self.start = start
        self.end = end
    }

    func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

/// 一次报表定位的结果：报告期区间与用于同比的对照期区间。
struct ReportPeriodSelection: Equatable, Sendable {
    let period: ReportPeriod
    let target: ReportTarget
    let reportRange: ReportDateRange
    let comparisonRange: ReportDateRange
}

/// 报表图表上的一个时间桶（日报按小时、月报按天等），可点开下钻。
struct ReportTimeBucket: Identifiable, Equatable, Sendable {
    enum Granularity: String, Codable, Hashable, Sendable {
        case hour
        case day
        case week
        case month
    }

    var id: Date { range.start }
    let range: ReportDateRange
    let granularity: Granularity
    let label: String
    let expense: Decimal
}

/// 纯日期计算器。周首固定为周一，不受用户地区的 firstWeekday 设置影响。
struct ReportPeriodCalculator {
    let calendar: Calendar
    let payday: Int

    init(calendar: Calendar = .current, payday: Int = 1) {
        self.calendar = calendar
        self.payday = min(max(payday, 1), 31)
    }

    func selection(for period: ReportPeriod, target: ReportTarget) -> ReportPeriodSelection {
        switch target {
        case .current(let referenceDate):
            return currentSelection(for: period, referenceDate: referenceDate, target: target)
        case .completed(let anchor):
            return completedSelection(
                for: period,
                reportStart: start(of: period, containing: anchor),
                target: target
            )
        case .scheduled(let triggerDate):
            if period == .daily {
                return currentSelection(for: period, referenceDate: triggerDate, target: target)
            }
            let containingStart = start(of: period, containing: triggerDate)
            return completedSelection(
                for: period,
                reportStart: previousStart(before: containingStart, period: period),
                target: target
            )
        }
    }

    func bucketRanges(for selection: ReportPeriodSelection) -> [ReportDateRange] {
        let range = selection.reportRange
        guard range.start < range.end else { return [] }

        var result: [ReportDateRange] = []
        var cursor = range.start
        while cursor < range.end {
            let naturalEnd: Date
            switch selection.period {
            case .daily:
                naturalEnd = calendar.date(byAdding: .hour, value: 1, to: cursor)!
            case .weekly, .payCycle:
                naturalEnd = calendar.date(byAdding: .day, value: 1, to: cursor)!
            case .monthly:
                let nextWeek = calendar.date(byAdding: .day, value: 7, to: mondayStart(containing: cursor))!
                naturalEnd = max(nextWeek, calendar.date(byAdding: .day, value: 1, to: cursor)!)
            case .yearly:
                naturalEnd = calendar.date(byAdding: .month, value: 1, to: cursor)!
            }
            let end = min(naturalEnd, range.end)
            result.append(ReportDateRange(start: cursor, end: end))
            cursor = end
        }
        return result
    }

    func completeRange(for period: ReportPeriod, containing date: Date) -> ReportDateRange {
        if period == .payCycle {
            let cycle = PayCycleService.cycle(containing: date, payday: payday, calendar: calendar)
            return ReportDateRange(start: cycle.start, end: cycle.end)
        }
        let start = start(of: period, containing: date)
        return ReportDateRange(start: start, end: nextStart(after: start, period: period))
    }

    func previousCompletedAnchor(for selection: ReportPeriodSelection) -> Date {
        previousStart(before: selection.reportRange.start, period: selection.period)
    }

    /// 返回下一完整周期的锚点；nil 表示下一步应回到当前进行中周期。
    func nextCompletedAnchor(
        for selection: ReportPeriodSelection,
        referenceDate: Date
    ) -> Date? {
        let nextStart = selection.reportRange.end
        return nextStart < start(of: selection.period, containing: referenceDate) ? nextStart : nil
    }

    func currentPeriodEnd(for period: ReportPeriod, referenceDate: Date) -> Date {
        completeRange(for: period, containing: referenceDate).end
    }

    func nextLocalMidnight(after date: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
    }

    private func currentSelection(
        for period: ReportPeriod,
        referenceDate: Date,
        target: ReportTarget
    ) -> ReportPeriodSelection {
        let containingStart = start(of: period, containing: referenceDate)
        let previousStart = previousStart(before: containingStart, period: period)
        let previousEnd = min(
            nextStart(after: previousStart, period: period),
            alignedEnd(from: containingStart, to: referenceDate, previousStart: previousStart)
        )
        return ReportPeriodSelection(
            period: period,
            target: target,
            reportRange: ReportDateRange(start: containingStart, end: max(containingStart, referenceDate)),
            comparisonRange: ReportDateRange(start: previousStart, end: max(previousStart, previousEnd))
        )
    }

    private func completedSelection(
        for period: ReportPeriod,
        reportStart: Date,
        target: ReportTarget
    ) -> ReportPeriodSelection {
        let reportEnd = nextStart(after: reportStart, period: period)
        let comparisonStart = previousStart(before: reportStart, period: period)
        return ReportPeriodSelection(
            period: period,
            target: target,
            reportRange: ReportDateRange(start: reportStart, end: reportEnd),
            comparisonRange: ReportDateRange(start: comparisonStart, end: reportStart)
        )
    }

    private func start(of period: ReportPeriod, containing date: Date) -> Date {
        switch period {
        case .daily:
            return calendar.startOfDay(for: date)
        case .weekly:
            return mondayStart(containing: date)
        case .monthly:
            return calendar.date(from: calendar.dateComponents([.calendar, .timeZone, .year, .month], from: date))!
        case .yearly:
            return calendar.date(from: calendar.dateComponents([.calendar, .timeZone, .year], from: date))!
        case .payCycle:
            return PayCycleService.cycle(containing: date, payday: payday, calendar: calendar).start
        }
    }

    private func mondayStart(containing date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day)!
    }

    private func previousStart(before start: Date, period: ReportPeriod) -> Date {
        if period == .payCycle {
            let previousDay = calendar.date(byAdding: .day, value: -1, to: start) ?? start
            return PayCycleService.cycle(containing: previousDay, payday: payday, calendar: calendar).start
        }
        return offset(start, by: -1, period: period)
    }

    private func nextStart(after start: Date, period: ReportPeriod) -> Date {
        if period == .payCycle {
            return PayCycleService.cycle(containing: start, payday: payday, calendar: calendar).end
        }
        return offset(start, by: 1, period: period)
    }

    private func offset(_ date: Date, by value: Int, period: ReportPeriod) -> Date {
        switch period {
        case .daily: return calendar.date(byAdding: .day, value: value, to: date)!
        case .weekly: return calendar.date(byAdding: .day, value: value * 7, to: date)!
        case .monthly: return calendar.date(byAdding: .month, value: value, to: date)!
        case .yearly: return calendar.date(byAdding: .year, value: value, to: date)!
        case .payCycle:
            preconditionFailure("发薪周期必须通过相邻周期边界计算")
        }
    }

    private func alignedEnd(from currentStart: Date, to currentEnd: Date, previousStart: Date) -> Date {
        let components = calendar.dateComponents(
            [.day, .hour, .minute, .second, .nanosecond],
            from: currentStart,
            to: currentEnd
        )
        return calendar.date(byAdding: components, to: previousStart) ?? previousStart
    }
}
