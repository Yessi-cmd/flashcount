import XCTest
@testable import FlashCount

final class QuickEntryBudgetHintTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }

    private func referenceDate() throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 1,
            day: 15,
            hour: 12
        )))
    }

    private func makeDraft(
        amount: Decimal?,
        category: FlashCount.Category? = nil,
        dailyBudgetOverride: Bool? = nil,
        isExpense: Bool = true
    ) -> QuickEntryBudgetDraft {
        QuickEntryBudgetDraft(
            amount: amount,
            isExpense: isExpense,
            category: category,
            dailyBudgetOverride: dailyBudgetOverride
        )
    }

    func testIncomeDraftHasNoHint() throws {
        let referenceDate = try referenceDate()
        let budget = Budget(monthlyLimit: 1_000, year: 2026, month: 1)

        let hint = QuickEntryBudgetHintCalculator.makeHint(
            budgets: [budget],
            transactions: [],
            ledger: nil,
            referenceDate: referenceDate,
            payday: 1,
            weekendMultiplier: 1,
            draft: makeDraft(amount: 10, isExpense: false),
            calendar: calendar
        )

        XCTAssertNil(hint)
    }

    func testMissingCurrentBudgetHasNoHint() throws {
        let referenceDate = try referenceDate()

        let hint = QuickEntryBudgetHintCalculator.makeHint(
            budgets: [],
            transactions: [],
            ledger: nil,
            referenceDate: referenceDate,
            payday: 1,
            weekendMultiplier: 1,
            draft: makeDraft(amount: 10),
            calendar: calendar
        )

        XCTAssertNil(hint)
    }

    func testEnteredAmountMovesHealthyHintTowardBudgetLine() throws {
        let referenceDate = try referenceDate()
        let cycle = PayCycleService.cycle(
            containing: referenceDate,
            payday: 1,
            calendar: calendar
        )
        let budget = Budget(
            monthlyLimit: 1_000,
            year: cycle.budgetYear,
            month: cycle.budgetMonth
        )
        let transaction = Transaction(
            amount: 100,
            isExpense: true,
            date: referenceDate
        )
        transaction.dailyBudgetOverride = true

        let before = try XCTUnwrap(QuickEntryBudgetHintCalculator.makeHint(
            budgets: [budget],
            transactions: [transaction],
            ledger: nil,
            referenceDate: referenceDate,
            payday: 1,
            weekendMultiplier: 1,
            draft: makeDraft(amount: nil),
            calendar: calendar
        ))
        XCTAssertEqual(before.level, .healthy)
        XCTAssertEqual(before.projectedAnalysis.totalSpent, 100)

        let after = try XCTUnwrap(QuickEntryBudgetHintCalculator.makeHint(
            budgets: [budget],
            transactions: [transaction],
            ledger: nil,
            referenceDate: referenceDate,
            payday: 1,
            weekendMultiplier: 1,
            draft: makeDraft(amount: 950, dailyBudgetOverride: true),
            calendar: calendar
        ))
        XCTAssertEqual(after.projectedAnalysis.totalSpent, 1_050)
        XCTAssertEqual(after.level, .danger)
        XCTAssertTrue(after.draftCountsTowardDailyBudget)
        XCTAssertTrue(after.text.contains("超"))
    }

    func testDraftExcludedFromDailyBudgetDoesNotChangeProjectedSpending() throws {
        let referenceDate = try referenceDate()
        let cycle = PayCycleService.cycle(
            containing: referenceDate,
            payday: 1,
            calendar: calendar
        )
        let budget = Budget(
            monthlyLimit: 1_000,
            year: cycle.budgetYear,
            month: cycle.budgetMonth
        )
        let transaction = Transaction(
            amount: 100,
            isExpense: true,
            date: referenceDate
        )
        transaction.dailyBudgetOverride = true

        let hint = try XCTUnwrap(QuickEntryBudgetHintCalculator.makeHint(
            budgets: [budget],
            transactions: [transaction],
            ledger: nil,
            referenceDate: referenceDate,
            payday: 1,
            weekendMultiplier: 1,
            draft: makeDraft(
                amount: 900,
                dailyBudgetOverride: false
            ),
            calendar: calendar
        ))

        XCTAssertEqual(hint.projectedAnalysis.totalSpent, 100)
        XCTAssertFalse(hint.draftCountsTowardDailyBudget)
        XCTAssertTrue(hint.text.contains("不计入日常预算"))
    }
}
