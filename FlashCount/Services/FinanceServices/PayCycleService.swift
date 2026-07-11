import Foundation

struct PayCycle {
    let start: Date
    let end: Date

    var budgetYear: Int {
        Calendar.current.component(.year, from: start)
    }

    var budgetMonth: Int {
        Calendar.current.component(.month, from: start)
    }

    var displayTitle: String {
        "\(start.shortDateString) - \(Calendar.current.date(byAdding: .day, value: -1, to: end)?.shortDateString ?? end.shortDateString)"
    }
}

enum PayCycleService {
    static func cycle(containing date: Date = Date(), payday: Int, calendar: Calendar = .current) -> PayCycle {
        let normalizedPayday = min(max(payday, 1), 31)
        let dayStart = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month], from: dayStart)
        let thisPayday = paydayDate(
            year: components.year ?? 2000,
            month: components.month ?? 1,
            payday: normalizedPayday,
            calendar: calendar
        )

        let start: Date
        if dayStart >= thisPayday {
            start = thisPayday
        } else {
            let previousMonth = calendar.date(byAdding: .month, value: -1, to: thisPayday) ?? thisPayday
            let previousComponents = calendar.dateComponents([.year, .month], from: previousMonth)
            start = paydayDate(
                year: previousComponents.year ?? components.year ?? 2000,
                month: previousComponents.month ?? components.month ?? 1,
                payday: normalizedPayday,
                calendar: calendar
            )
        }

        let nextMonth = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        let nextComponents = calendar.dateComponents([.year, .month], from: nextMonth)
        let end = paydayDate(
            year: nextComponents.year ?? components.year ?? 2000,
            month: nextComponents.month ?? components.month ?? 1,
            payday: normalizedPayday,
            calendar: calendar
        )

        return PayCycle(start: start, end: end)
    }

    private static func paydayDate(year: Int, month: Int, payday: Int, calendar: Calendar) -> Date {
        let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        let maxDay = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 28
        return calendar.date(from: DateComponents(year: year, month: month, day: min(payday, maxDay))) ?? firstOfMonth
    }
}
