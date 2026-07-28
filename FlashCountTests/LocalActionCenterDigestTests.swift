import XCTest
@testable import FlashCount

@MainActor
final class LocalActionCenterDigestTests: XCTestCase {
    func testDigestChangesWhenBudgetValueChanges() {
        let budget = Budget(monthlyLimit: 1_000, year: 2026, month: 7)
        let before = makeDigest(budgets: [budget])

        budget.monthlyLimit = 2_000

        XCTAssertNotEqual(before, makeDigest(budgets: [budget]))
    }

    private func makeDigest(budgets: [Budget]) -> Int {
        LocalActionCenterDigest.make(
            budgets: budgets,
            transactions: [],
            categories: [],
            recurringRules: [],
            occurrences: [],
            installmentBills: [],
            reminders: [],
            payday: 15,
            weekendBudgetMultiplierPercent: 100,
            dismissedSuggestionFingerprints: []
        )
    }
}
