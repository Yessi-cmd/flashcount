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

    func testDigestChangesWhenCashPoolBalanceChanges() {
        let item = CashPoolItem(name: "现金", kind: .cash, amount: 1_000)
        let before = makeDigest(budgets: [], cashPoolItems: [item])

        item.amount = 500

        XCTAssertNotEqual(
            before,
            makeDigest(budgets: [], cashPoolItems: [item])
        )
    }

    private func makeDigest(
        budgets: [Budget],
        cashPoolItems: [CashPoolItem] = []
    ) -> Int {
        LocalActionCenterDigest.make(
            budgets: budgets,
            transactions: [],
            categories: [],
            recurringRules: [],
            occurrences: [],
            installmentBills: [],
            reminders: [],
            cashPoolItems: cashPoolItems,
            cashPoolStates: [],
            payday: 15,
            weekendBudgetMultiplierPercent: 100,
            dismissedSuggestionFingerprints: []
        )
    }
}
