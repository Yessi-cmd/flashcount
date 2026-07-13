import XCTest
@testable import FlashCount

final class AppRoutingTests: XCTestCase {
    func testQuickEntryDeepLinkParsesOnlyExpectedSchemeAndHost() throws {
        XCTAssertEqual(AppDeepLink(url: AppDeepLink.quickEntryURL), .quickEntry)
        XCTAssertNil(AppDeepLink(url: try XCTUnwrap(URL(string: "https://quick-entry"))))
        XCTAssertNil(AppDeepLink(url: try XCTUnwrap(URL(string: "flashcount://unknown"))))
    }

    func testReportDeepLinkCarriesTypedPeriod() throws {
        let url = try XCTUnwrap(URL(string: "flashcount://report?period=%E6%9C%88%E6%8A%A5"))
        XCTAssertEqual(AppDeepLink(url: url), .report(.monthly))
    }
}
