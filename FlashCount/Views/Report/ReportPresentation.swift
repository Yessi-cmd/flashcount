import Foundation

/// 报表区间的显示文案与对应的无障碍朗读文案（后者需要完整日期，不能用缩写）。
struct ReportRangePresentation: Equatable {
    let title: String
    let accessibilityLabel: String
}

/// 报表区间的文案格式化。区间以 `[start, end)` 存储，展示时需换算成含尾日。
struct ReportDateRangeFormatter {
    let calendar: Calendar
    let locale: Locale

    init(
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "zh_CN")
    ) {
        self.calendar = calendar
        self.locale = locale
    }

    func reportRange(_ range: ReportDateRange, period: ReportPeriod) -> ReportRangePresentation {
        let endDate = inclusiveEndDate(for: range)
        let formatter = makeFormatter()
        formatter.dateFormat = period == .yearly ? "yyyy年M月d日" : "yyyy年M月d日"
        let startText = formatter.string(from: range.start)
        let endText = formatter.string(from: endDate)
        let dateText = startText == endText ? startText : "\(startText)–\(endText)"

        guard !isMidnight(range.end) else {
            return ReportRangePresentation(title: dateText, accessibilityLabel: dateText)
        }

        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: range.end)
        return ReportRangePresentation(
            title: "\(dateText) · 截至 \(time)",
            accessibilityLabel: "\(dateText)，截至 \(time)"
        )
    }

    func bucketLabel(for range: ReportDateRange, granularity: ReportTimeBucket.Granularity) -> String {
        let formatter = makeFormatter()
        switch granularity {
        case .hour:
            formatter.dateFormat = "H时"
            return formatter.string(from: range.start)
        case .day:
            formatter.dateFormat = "EEE"
            return formatter.string(from: range.start)
        case .week:
            formatter.dateFormat = "M月d日"
            let start = formatter.string(from: range.start)
            let end = formatter.string(from: inclusiveEndDate(for: range))
            return start == end ? start : "\(start)–\(end)"
        case .month:
            formatter.dateFormat = "M月"
            return formatter.string(from: range.start)
        }
    }

    func inclusiveEndDate(for range: ReportDateRange) -> Date {
        guard isMidnight(range.end) else { return range.end }
        return calendar.date(byAdding: .day, value: -1, to: range.end) ?? range.start
    }

    private func isMidnight(_ date: Date) -> Bool {
        calendar.isDate(date, equalTo: calendar.startOfDay(for: date), toGranularity: .second)
    }

    private func makeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        return formatter
    }
}

/// 报表里的指标种类，决定同比变化该往哪个方向解读。
enum ReportMetricKind: Equatable {
    case expense
    case income
}

/// 同比变化的方向。
enum ReportChangeDirection: Equatable {
    case increase
    case decrease
    case unchanged
}

/// 一处同比变化的呈现。支出增加是坏消息、收入增加是好消息，
/// 所以「涨」与「好坏」必须分开表达，不能只按符号配色。
struct ReportChangePresentation: Equatable {
    let text: String
    let direction: ReportChangeDirection
    let isFavorable: Bool?

    static func make(change: Double, metric: ReportMetricKind) -> ReportChangePresentation {
        let direction: ReportChangeDirection
        if abs(change) < 0.000_001 {
            direction = .unchanged
        } else {
            direction = change > 0 ? .increase : .decrease
        }

        let favorable: Bool?
        switch direction {
        case .unchanged:
            favorable = nil
        case .increase:
            favorable = metric == .income
        case .decrease:
            favorable = metric == .expense
        }

        return ReportChangePresentation(
            text: ReportPercentageFormatter.changeRate(change),
            direction: direction,
            isFavorable: favorable
        )
    }
}

/// 报表百分比格式化，含极端值的封顶显示。
enum ReportPercentageFormatter {
    static func categoryShare(_ value: Double) -> String {
        let finite = value.isFinite ? value : 0
        let percent = Int((min(max(finite, 0), 1) * 100).rounded())
        return "\(percent)%"
    }

    static func changeRate(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        let absolute = abs(value)
        if absolute > 1 { return "100%+" }
        return "\(Int((absolute * 100).rounded()))%"
    }
}
