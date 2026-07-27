import Foundation

/// 一个发薪周期的区间 `[start, end)`。
///
/// `budgetYear`/`budgetMonth` 取自 `start`，预算就按这两个值归属——所以
/// 「预算的月份」指周期归属月，不是自然月。
struct PayCycle {
    let start: Date
    let end: Date
    let calendar: Calendar

    var budgetYear: Int {
        calendar.component(.year, from: start)
    }

    var budgetMonth: Int {
        calendar.component(.month, from: start)
    }

    var displayTitle: String {
        "\(start.shortDateString) - \(calendar.date(byAdding: .day, value: -1, to: end)?.shortDateString ?? end.shortDateString)"
    }
}

/// 由发薪日（每月几号）推算周期区间。
///
/// 全 App 的「本周期」「上周期」都从这里来，发薪日因此是最关键的一个设置：
/// 它错了，预算与报表的每个数字都跟着错，而界面不会有任何提示——这正是
/// 引导页必须问一次的原因。发薪日会夹到 1…31，某个月没有这一天时自动
/// 落到当月最后一天。
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

        return PayCycle(start: start, end: end, calendar: calendar)
    }

    private static func paydayDate(year: Int, month: Int, payday: Int, calendar: Calendar) -> Date {
        let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        let maxDay = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 28
        return calendar.date(from: DateComponents(year: year, month: month, day: min(payday, maxDay))) ?? firstOfMonth
    }
}
