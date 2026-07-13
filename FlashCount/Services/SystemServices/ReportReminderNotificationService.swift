import Foundation
import UserNotifications

protocol ReportReminderNotificationScheduling {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async -> Bool
    func replaceSchedule(with preferences: ReportReminderPreferences) async throws
    func cancelAll() async
}

struct ReportReminderRequestPlan: Equatable {
    let identifier: String
    let period: ReportPeriod
    let dateComponents: DateComponents
    let repeats: Bool
    let title: String
    let body: String
}

/// 将用户偏好转换为可测试的本地通知计划。
/// 日报、周报使用系统重复通知；月报、年报滚动安排未来日期，以正确处理 29/30/31 日。
enum ReportReminderSchedulePlanner {
    static let identifierPrefix = "flashcount.report."

    static func plans(
        for preferences: ReportReminderPreferences,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [ReportReminderRequestPlan] {
        let preferences = preferences.normalized()
        var result: [ReportReminderRequestPlan] = []

        if preferences.enabledPeriods.contains(.daily) {
            result.append(plan(
                identifier: "\(identifierPrefix)daily",
                period: .daily,
                components: DateComponents(
                    hour: preferences.deliveryTime.hour,
                    minute: preferences.deliveryTime.minute
                ),
                repeats: true
            ))
        }

        if preferences.enabledPeriods.contains(.weekly) {
            var components = DateComponents()
            components.weekday = preferences.weeklyDeliveryWeekday
            components.hour = preferences.deliveryTime.hour
            components.minute = preferences.deliveryTime.minute
            result.append(plan(
                identifier: "\(identifierPrefix)weekly",
                period: .weekly,
                components: components,
                repeats: true
            ))
        }

        if preferences.enabledPeriods.contains(.monthly) {
            let dates = futureMonthlyDates(
                day: preferences.monthlyDeliveryDay,
                time: preferences.deliveryTime,
                count: 12,
                after: referenceDate,
                calendar: calendar
            )
            for (index, date) in dates.enumerated() {
                result.append(plan(
                    identifier: "\(identifierPrefix)monthly.\(index)",
                    period: .monthly,
                    components: calendar.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: date
                    ),
                    repeats: false
                ))
            }
        }

        if preferences.enabledPeriods.contains(.yearly) {
            let dates = futureYearlyDates(
                month: preferences.yearlyDeliveryMonth,
                day: preferences.yearlyDeliveryDay,
                time: preferences.deliveryTime,
                count: 3,
                after: referenceDate,
                calendar: calendar
            )
            for (index, date) in dates.enumerated() {
                result.append(plan(
                    identifier: "\(identifierPrefix)yearly.\(index)",
                    period: .yearly,
                    components: calendar.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: date
                    ),
                    repeats: false
                ))
            }
        }

        return result
    }

    private static func plan(
        identifier: String,
        period: ReportPeriod,
        components: DateComponents,
        repeats: Bool
    ) -> ReportReminderRequestPlan {
        ReportReminderRequestPlan(
            identifier: identifier,
            period: period,
            dateComponents: components,
            repeats: repeats,
            title: "你的\(period.rawValue)已准备好",
            body: "打开 FlashCount，看看这一周期的收支变化与消费洞察。"
        )
    }

    private static func futureMonthlyDates(
        day: Int,
        time: ReportReminderTime,
        count: Int,
        after referenceDate: Date,
        calendar: Calendar
    ) -> [Date] {
        guard count > 0 else { return [] }
        let monthStart = calendar.date(
            from: calendar.dateComponents([.calendar, .timeZone, .year, .month], from: referenceDate)
        ) ?? referenceDate
        var dates: [Date] = []
        var offset = 0

        while dates.count < count, offset < count + 24 {
            guard let targetMonth = calendar.date(byAdding: .month, value: offset, to: monthStart),
                  let date = clampedDate(
                    year: calendar.component(.year, from: targetMonth),
                    month: calendar.component(.month, from: targetMonth),
                    day: day,
                    time: time,
                    calendar: calendar
                  ) else {
                offset += 1
                continue
            }
            if date > referenceDate { dates.append(date) }
            offset += 1
        }
        return dates
    }

    private static func futureYearlyDates(
        month: Int,
        day: Int,
        time: ReportReminderTime,
        count: Int,
        after referenceDate: Date,
        calendar: Calendar
    ) -> [Date] {
        guard count > 0 else { return [] }
        let startYear = calendar.component(.year, from: referenceDate)
        var dates: [Date] = []
        var offset = 0

        while dates.count < count, offset < count + 4 {
            if let date = clampedDate(
                year: startYear + offset,
                month: month,
                day: day,
                time: time,
                calendar: calendar
            ), date > referenceDate {
                dates.append(date)
            }
            offset += 1
        }
        return dates
    }

    private static func clampedDate(
        year: Int,
        month: Int,
        day: Int,
        time: ReportReminderTime,
        calendar: Calendar
    ) -> Date? {
        guard let monthDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let dayRange = calendar.range(of: .day, in: .month, for: monthDate) else {
            return nil
        }
        return calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: min(max(day, 1), dayRange.count),
            hour: time.hour,
            minute: time.minute
        ))
    }
}

enum ReportReminderNotificationService {
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func replaceSchedule(with preferences: ReportReminderPreferences) async throws {
        await cancelAll()
        let center = UNUserNotificationCenter.current()
        do {
            for plan in ReportReminderSchedulePlanner.plans(for: preferences) {
                let content = UNMutableNotificationContent()
                content.title = plan.title
                content.body = plan.body
                content.sound = .default
                content.userInfo = [ReportRoute.notificationPeriodUserInfoKey: plan.period.rawValue]

                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: plan.dateComponents,
                    repeats: plan.repeats
                )
                try await center.add(UNNotificationRequest(
                    identifier: plan.identifier,
                    content: content,
                    trigger: trigger
                ))
            }
        } catch {
            await cancelAll()
            throw error
        }
    }

    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let requests = await pendingRequests(from: center)
        let identifiers = requests
            .map(\.identifier)
            .filter { $0.hasPrefix(ReportReminderSchedulePlanner.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    static func refreshStoredScheduleIfAuthorized() async {
        let preferences = UserDefaultsReportReminderPreferencesStore().load()
        guard !preferences.enabledPeriods.isEmpty else {
            await cancelAll()
            return
        }
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        try? await replaceSchedule(with: preferences)
    }

    private static func pendingRequests(from center: UNUserNotificationCenter) async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }
}

struct SystemReportReminderNotificationScheduler: ReportReminderNotificationScheduling {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await ReportReminderNotificationService.authorizationStatus()
    }

    func requestAuthorization() async -> Bool {
        await ReportReminderNotificationService.requestAuthorization()
    }

    func replaceSchedule(with preferences: ReportReminderPreferences) async throws {
        try await ReportReminderNotificationService.replaceSchedule(with: preferences)
    }

    func cancelAll() async {
        await ReportReminderNotificationService.cancelAll()
    }
}
