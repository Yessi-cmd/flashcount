import Foundation

/// 支持的报表周期。
enum ReportPeriod: String, CaseIterable, Codable, Hashable, Sendable {
    case daily = "日报"
    case weekly = "周报"
    case monthly = "月报"
    case yearly = "年报"

    var bucketGranularity: ReportTimeBucket.Granularity {
        switch self {
        case .daily: return .hour
        case .weekly: return .day
        case .monthly: return .week
        case .yearly: return .month
        }
    }
}

/// 报表所针对的时间。当前周期用于应用内预览；上一完整周期用于定时报表。
enum ReportTarget: Equatable, Sendable {
    case current(referenceDate: Date)
    case mostRecentlyCompleted(referenceDate: Date)

    var referenceDate: Date {
        switch self {
        case .current(let date), .mostRecentlyCompleted(let date): return date
        }
    }

    static func scheduled(period: ReportPeriod, triggerDate: Date) -> ReportTarget {
        period == .daily
            ? .current(referenceDate: triggerDate)
            : .mostRecentlyCompleted(referenceDate: triggerDate)
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

struct ReportPeriodSelection: Equatable, Sendable {
    let period: ReportPeriod
    let target: ReportTarget
    let reportRange: ReportDateRange
    let comparisonRange: ReportDateRange
}

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

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func selection(for period: ReportPeriod, target: ReportTarget) -> ReportPeriodSelection {
        let referenceDate = target.referenceDate
        let containingStart = start(of: period, containing: referenceDate)

        switch target {
        case .current:
            let previousStart = offset(containingStart, by: -1, period: period)
            let previousEnd = min(
                offset(previousStart, by: 1, period: period),
                alignedEnd(from: containingStart, to: referenceDate, previousStart: previousStart)
            )
            return ReportPeriodSelection(
                period: period,
                target: target,
                reportRange: ReportDateRange(start: containingStart, end: max(containingStart, referenceDate)),
                comparisonRange: ReportDateRange(start: previousStart, end: max(previousStart, previousEnd))
            )

        case .mostRecentlyCompleted:
            let reportStart = offset(containingStart, by: -1, period: period)
            let comparisonStart = offset(reportStart, by: -1, period: period)
            return ReportPeriodSelection(
                period: period,
                target: target,
                reportRange: ReportDateRange(start: reportStart, end: containingStart),
                comparisonRange: ReportDateRange(start: comparisonStart, end: reportStart)
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
            case .weekly:
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
        }
    }

    private func mondayStart(containing date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day)!
    }

    private func offset(_ date: Date, by value: Int, period: ReportPeriod) -> Date {
        switch period {
        case .daily: return calendar.date(byAdding: .day, value: value, to: date)!
        case .weekly: return calendar.date(byAdding: .day, value: value * 7, to: date)!
        case .monthly: return calendar.date(byAdding: .month, value: value, to: date)!
        case .yearly: return calendar.date(byAdding: .year, value: value, to: date)!
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
