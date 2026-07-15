import Foundation

/// 报表通知与 App 内导航之间的持久化路由桥。
/// UserDefaults 覆盖通知冷启动、SwiftUI 根视图尚未创建的场景。
enum ReportRoute {
    struct Request: Codable, Equatable, Identifiable {
        enum Target: Codable, Equatable {
            case current
            case scheduled(deliveredAt: Date)
        }

        let id: UUID
        let period: ReportPeriod
        let target: Target

        init(id: UUID = UUID(), period: ReportPeriod, target: Target) {
            self.id = id
            self.period = period
            self.target = target
        }
    }

    static let requestKey = "shouldShowReport"
    static let periodKey = "requestedReportPeriod"
    static let payloadKey = "reportRoutePayload.v2"
    static let notificationPeriodUserInfoKey = "flashcount.report.period"

    static func requestCurrent(
        period: ReportPeriod,
        userDefaults: UserDefaults = .standard
    ) {
        request(Request(period: period, target: .current), userDefaults: userDefaults)
    }

    static func requestScheduled(
        period: ReportPeriod,
        deliveredAt: Date,
        userDefaults: UserDefaults = .standard
    ) {
        request(
            Request(period: period, target: .scheduled(deliveredAt: deliveredAt)),
            userDefaults: userDefaults
        )
    }

    static func requestFromNotification(
        userInfo: [AnyHashable: Any],
        deliveredAt: Date,
        userDefaults: UserDefaults = .standard
    ) {
        guard let rawPeriod = userInfo[notificationPeriodUserInfoKey] as? String,
              let period = ReportPeriod(rawValue: rawPeriod) else { return }
        requestScheduled(period: period, deliveredAt: deliveredAt, userDefaults: userDefaults)
    }

    static func consume(userDefaults: UserDefaults = .standard) -> Request? {
        defer {
            userDefaults.removeObject(forKey: payloadKey)
            userDefaults.removeObject(forKey: periodKey)
        }

        if let data = userDefaults.data(forKey: payloadKey),
           let request = try? decoder.decode(Request.self, from: data) {
            return request
        }

        guard let rawPeriod = userDefaults.string(forKey: periodKey),
              let period = ReportPeriod(rawValue: rawPeriod) else { return nil }
        return Request(period: period, target: .current)
    }

    /// 兼容旧调用方；普通 App 内导航始终表示当前周期。
    static func request(
        period: ReportPeriod,
        userDefaults: UserDefaults = .standard
    ) {
        requestCurrent(period: period, userDefaults: userDefaults)
    }

    private static func request(_ request: Request, userDefaults: UserDefaults) {
        if let data = try? encoder.encode(request) {
            userDefaults.set(data, forKey: payloadKey)
        }
        // 保留旧版本可理解的 period 键，便于降级和未消费请求迁移。
        userDefaults.set(request.period.rawValue, forKey: periodKey)
        userDefaults.set(true, forKey: requestKey)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
