import Foundation

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
