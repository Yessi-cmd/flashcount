import XCTest
@testable import FlashCount

final class AppRoutingTests: XCTestCase {
    func testQuickEntryRouteRequestsAndConsumesExactlyOnce() throws {
        let suiteName = "AppRoutingTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(QuickEntryRoute.consume(userDefaults: defaults))

        QuickEntryRoute.request(userDefaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: QuickEntryRoute.requestKey))
        XCTAssertTrue(QuickEntryRoute.consume(userDefaults: defaults))
        XCTAssertFalse(defaults.bool(forKey: QuickEntryRoute.requestKey))
        XCTAssertFalse(QuickEntryRoute.consume(userDefaults: defaults))
    }

    func testQuickEntryDeepLinkParsesOnlyExpectedSchemeAndHost() throws {
        XCTAssertEqual(AppDeepLink(url: AppDeepLink.quickEntryURL), .quickEntry)
        XCTAssertNil(AppDeepLink(url: try XCTUnwrap(URL(string: "https://quick-entry"))))
        XCTAssertNil(AppDeepLink(url: try XCTUnwrap(URL(string: "flashcount://unknown"))))
    }

    func testReportDeepLinkCarriesTypedPeriod() throws {
        let url = try XCTUnwrap(URL(string: "flashcount://report?period=%E6%9C%88%E6%8A%A5"))
        XCTAssertEqual(AppDeepLink(url: url), .report(.monthly))

        let payCycleURL = try XCTUnwrap(URL(string: "flashcount://report?period=%E5%91%A8%E6%9C%9F%E6%8A%A5"))
        XCTAssertEqual(AppDeepLink(url: payCycleURL), .report(.payCycle))
    }

    func testLegacyReportRouteFallsBackToCurrentTarget() throws {
        let suiteName = "AppRoutingTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: ReportRoute.requestKey)
        defaults.set(ReportPeriod.weekly.rawValue, forKey: ReportRoute.periodKey)

        XCTAssertEqual(
            ReportRoute.consume(userDefaults: defaults)?.target,
            .current
        )
    }

    func testNotificationRouteUsesDeliveredDate() throws {
        let suiteName = "AppRoutingTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let deliveredAt = Date(timeIntervalSince1970: 123_456)

        ReportRoute.requestFromNotification(
            userInfo: [ReportRoute.notificationPeriodUserInfoKey: ReportPeriod.monthly.rawValue],
            deliveredAt: deliveredAt,
            userDefaults: defaults
        )

        XCTAssertEqual(
            ReportRoute.consume(userDefaults: defaults)?.target,
            .scheduled(deliveredAt: deliveredAt)
        )
    }

    func testForegroundNotificationRequestsInAppReportSheet() throws {
        let suiteName = "AppRoutingTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let deliveredAt = Date(timeIntervalSince1970: 234_567)

        XCTAssertTrue(ReportRoute.requestFromNotification(
            userInfo: [ReportRoute.notificationPeriodUserInfoKey: ReportPeriod.daily.rawValue],
            deliveredAt: deliveredAt,
            presentation: .foregroundSheet,
            userDefaults: defaults
        ))

        let request = try XCTUnwrap(ReportRoute.consume(userDefaults: defaults))
        XCTAssertEqual(request.period, .daily)
        XCTAssertEqual(request.target, .scheduled(deliveredAt: deliveredAt))
        XCTAssertEqual(request.resolvedPresentation, .foregroundSheet)
    }

    func testNonReportNotificationDoesNotCreateReportRoute() throws {
        let suiteName = "AppRoutingTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(ReportRoute.requestFromNotification(
            userInfo: [:],
            deliveredAt: Date(),
            presentation: .foregroundSheet,
            userDefaults: defaults
        ))
        XCTAssertFalse(defaults.bool(forKey: ReportRoute.requestKey))
        XCTAssertNil(ReportRoute.consume(userDefaults: defaults))
    }
}
