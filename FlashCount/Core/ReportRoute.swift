import Foundation

/// 报表通知与 App 内导航之间的轻量路由桥。
/// 使用 UserDefaults 是为了覆盖通知冷启动、SwiftUI 根视图尚未创建的情况。
enum ReportRoute {
    static let requestKey = "shouldShowReport"
    static let periodKey = "requestedReportPeriod"
    static let notificationPeriodUserInfoKey = "flashcount.report.period"

    static func request(
        period: ReportPeriod,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(period.rawValue, forKey: periodKey)
        userDefaults.set(true, forKey: requestKey)
    }
}
