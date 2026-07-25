import XCTest
@testable import FlashCount

final class MoneyValidationTests: XCTestCase {
    func testPositiveValidationAcceptsDecimalAndLeadingDot() throws {
        XCTAssertEqual(
            try? MoneyValidation.parse("12.50", requirement: .positive).get(),
            Decimal(string: "12.50")
        )
        XCTAssertEqual(
            try? MoneyValidation.parse(".5", requirement: .positive).get(),
            Decimal(string: "0.5")
        )
    }

    func testPositiveValidationRejectsEmptyZeroAndIncompleteInput() {
        XCTAssertEqual(
            MoneyValidation.parse("", requirement: .positive),
            .failure(.empty)
        )
        XCTAssertEqual(
            MoneyValidation.parse("0", requirement: .positive),
            .failure(.mustBePositive)
        )
        XCTAssertEqual(
            MoneyValidation.parse(".", requirement: .positive),
            .failure(.invalidFormat)
        )
        XCTAssertEqual(
            MoneyValidation.parse("0.", requirement: .positive),
            .failure(.invalidFormat)
        )
    }

    func testNonNegativeValidationAllowsZeroAndRejectsNegative() {
        XCTAssertEqual(
            MoneyValidation.parse("0", requirement: .nonNegative),
            .success(0)
        )
        XCTAssertEqual(
            MoneyValidation.parse("-1", requirement: .nonNegative),
            .failure(.mustBeNonNegative)
        )
    }

    func testValidationRejectsExponentAndMultipleDecimalPoints() {
        XCTAssertEqual(
            MoneyValidation.parse("1e3", requirement: .positive),
            .failure(.invalidFormat)
        )
        XCTAssertEqual(
            MoneyValidation.parse("1.2.3", requirement: .positive),
            .failure(.invalidFormat)
        )
    }

    func testDebounceGateAcceptsOnlyLatestNonCancelledQuery() {
        XCTAssertTrue(LedgerSearchQueryGate.accepts(query: "咖啡", latestQuery: "咖啡", isCancelled: false))
        XCTAssertFalse(LedgerSearchQueryGate.accepts(query: "咖", latestQuery: "咖啡", isCancelled: false))
        XCTAssertFalse(LedgerSearchQueryGate.accepts(query: "咖啡", latestQuery: "咖啡", isCancelled: true))
    }
}
