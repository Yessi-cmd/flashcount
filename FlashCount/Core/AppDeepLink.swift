import Foundation

/// App 支持的 `flashcount://` 深链。仅两个入口：快速记账与指定周期的报表。
/// 解析失败一律返回 nil，外部传进来的 URL 不该让 App 走进未定义状态。
enum AppDeepLink: Equatable {
    static let scheme = "flashcount"
    static let quickEntryURL = URL(string: "\(scheme)://quick-entry")!

    case quickEntry
    case report(ReportPeriod)

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        switch url.host?.lowercased() {
        case "quick-entry":
            self = .quickEntry
        case "report":
            let rawPeriod = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "period" })?
                .value
            guard let rawPeriod,
                  let period = ReportPeriod(rawValue: rawPeriod) else { return nil }
            self = .report(period)
        default:
            return nil
        }
    }
}
