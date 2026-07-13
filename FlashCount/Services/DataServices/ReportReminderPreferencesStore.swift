import Foundation

struct ReportReminderTime: Codable, Equatable, Sendable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }
}

/// 报表提醒的持久化偏好；具体通知调度由通知领域负责。
struct ReportReminderPreferences: Codable, Equatable, Sendable {
    var enabledPeriods: Set<ReportPeriod>
    var deliveryTime: ReportReminderTime
    /// Calendar weekday：1 为周日，2 为周一。
    var weeklyDeliveryWeekday: Int
    var monthlyDeliveryDay: Int
    var yearlyDeliveryMonth: Int
    var yearlyDeliveryDay: Int

    init(
        enabledPeriods: Set<ReportPeriod> = [],
        deliveryTime: ReportReminderTime = ReportReminderTime(hour: 20, minute: 0),
        weeklyDeliveryWeekday: Int = 2,
        monthlyDeliveryDay: Int = 1,
        yearlyDeliveryMonth: Int = 1,
        yearlyDeliveryDay: Int = 1
    ) {
        self.enabledPeriods = enabledPeriods
        self.deliveryTime = deliveryTime
        self.weeklyDeliveryWeekday = min(max(weeklyDeliveryWeekday, 1), 7)
        self.monthlyDeliveryDay = min(max(monthlyDeliveryDay, 1), 31)
        self.yearlyDeliveryMonth = min(max(yearlyDeliveryMonth, 1), 12)
        self.yearlyDeliveryDay = min(max(yearlyDeliveryDay, 1), 31)
    }

    static let `default` = ReportReminderPreferences()

    func normalized() -> ReportReminderPreferences {
        ReportReminderPreferences(
            enabledPeriods: enabledPeriods,
            deliveryTime: ReportReminderTime(hour: deliveryTime.hour, minute: deliveryTime.minute),
            weeklyDeliveryWeekday: weeklyDeliveryWeekday,
            monthlyDeliveryDay: monthlyDeliveryDay,
            yearlyDeliveryMonth: yearlyDeliveryMonth,
            yearlyDeliveryDay: yearlyDeliveryDay
        )
    }
}

protocol ReportReminderPreferencesStoring {
    func load() -> ReportReminderPreferences
    func save(_ preferences: ReportReminderPreferences) throws
}

struct UserDefaultsReportReminderPreferencesStore: ReportReminderPreferencesStoring {
    static let defaultKey = "reportReminderPreferences.v1"

    private let userDefaults: UserDefaults
    private let key: String

    init(userDefaults: UserDefaults = .standard, key: String = Self.defaultKey) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func load() -> ReportReminderPreferences {
        guard let data = userDefaults.data(forKey: key),
              let preferences = try? JSONDecoder().decode(ReportReminderPreferences.self, from: data)
        else {
            return .default
        }
        return preferences.normalized()
    }

    func save(_ preferences: ReportReminderPreferences) throws {
        let data = try JSONEncoder().encode(preferences.normalized())
        userDefaults.set(data, forKey: key)
    }
}
