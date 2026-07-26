import Foundation

/// 连续记账天数的共享纯逻辑。
/// 数据层用它判断回溯到哪里可以停止扫描，计算层用它得出最终天数——
/// 两侧必须共用同一套边界语义，否则「扫到哪」和「算到哪」会悄悄错位。
enum ReportStreakCalculator {
    /// 报告期结束时刻对应的最后一个可计入自然日。
    /// 半开区间正好结束在午夜时，那一天尚未开始，应回退一天。
    static func referenceDay(endingBefore end: Date, calendar: Calendar) -> Date {
        if calendar.isDate(end, equalTo: calendar.startOfDay(for: end), toGranularity: .second) {
            let previousDay = calendar.date(byAdding: .day, value: -1, to: end) ?? end
            return calendar.startOfDay(for: previousDay)
        }
        return calendar.startOfDay(for: end)
    }

    /// 连续记账天数。允许最后一天尚未记账（宽限一天）。
    static func streak(endingBefore end: Date, loggedDays: Set<Date>, calendar: Calendar) -> Int {
        guard var day = streakStartDay(endingBefore: end, loggedDays: loggedDays, calendar: calendar) else {
            return 0
        }
        var streak = 0
        while loggedDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// 连续链是否一路未断地延伸到 `boundary` 当天或更早。
    /// 为真表示更早的数据仍可能延长它，数据层需要继续向前取。
    static func extendsBefore(
        _ boundary: Date,
        endingBefore end: Date,
        loggedDays: Set<Date>,
        calendar: Calendar
    ) -> Bool {
        guard var day = streakStartDay(endingBefore: end, loggedDays: loggedDays, calendar: calendar) else {
            return false
        }
        let boundaryDay = calendar.startOfDay(for: boundary)
        while loggedDays.contains(day) {
            if day <= boundaryDay { return true }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { return false }
            day = previous
        }
        return false
    }

    private static func streakStartDay(
        endingBefore end: Date,
        loggedDays: Set<Date>,
        calendar: Calendar
    ) -> Date? {
        let reference = referenceDay(endingBefore: end, calendar: calendar)
        if loggedDays.contains(reference) { return reference }
        guard let previous = calendar.date(byAdding: .day, value: -1, to: reference),
              loggedDays.contains(previous) else { return nil }
        return previous
    }
}
