import Foundation

struct ReportRangePresentation: Equatable {
    let title: String
    let accessibilityLabel: String
}

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

enum ReportMetricKind: Equatable {
    case expense
    case income
}

enum ReportChangeDirection: Equatable {
    case increase
    case decrease
    case unchanged
}

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
