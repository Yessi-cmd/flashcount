import XCTest
@testable import FlashCount

@MainActor
final class RoutineSpendingProfileTests: XCTestCase {
    func testCompleteRecordedWeeksProduceExplainablePercentiles() throws {
        let reference = try date(2026, 7, 27, 12)
        let weeklyAmounts = (1...8).map { Decimal($0 * 70) }
        let transactions = try weeklyAmounts.enumerated().map { index, amount in
            try routineTransaction(
                amount: amount,
                date: dateInCompletedWeek(index + 1, reference: reference)
            )
        }

        let profile = try XCTUnwrap(
            RoutineSpendingProfile.calculate(
                transactions: transactions,
                referenceDate: reference,
                calendar: calendar,
                lookbackDays: 90
            )
        )

        XCTAssertEqual(profile.observedWeekCount, 8)
        XCTAssertEqual(profile.qualifyingTransactionCount, 8)
        XCTAssertEqual(profile.dataBasis, .sufficient)
        XCTAssertTrue(profile.supportsRange)
        XCTAssertEqual(profile.lighterDailyExpense, 24)
        XCTAssertEqual(profile.typicalDailyExpense, 45)
        XCTAssertEqual(profile.higherDailyExpense, 66)
    }

    func testBlankWeeksAreMissingButRecordedZeroRoutineWeeksCount() throws {
        let reference = try date(2026, 7, 27, 12)
        let routine = try routineTransaction(
            amount: 140,
            date: dateInCompletedWeek(1, reference: reference)
        )
        let incomeOnlyWeek = Transaction(
            amount: 1_000,
            isExpense: false,
            date: try dateInCompletedWeek(3, reference: reference)
        )

        let profile = try XCTUnwrap(
            RoutineSpendingProfile.calculate(
                transactions: [routine, incomeOnlyWeek],
                referenceDate: reference,
                calendar: calendar,
                lookbackDays: 90
            )
        )

        XCTAssertEqual(profile.observedWeekCount, 2, "完全空白的周不应被当成零消费")
        XCTAssertEqual(profile.weeklyTotals.sorted(), [0, 140])
        XCTAssertEqual(profile.typicalDailyExpense, 10)
        XCTAssertEqual(profile.dataBasis, .preliminary)
        XCTAssertFalse(profile.supportsRange)
        XCTAssertEqual(profile.lighterDailyExpense, profile.typicalDailyExpense)
        XCTAssertEqual(profile.higherDailyExpense, profile.typicalDailyExpense)
    }

    func testCurrentWeekRecurringAndOutOfScopeExpensesDoNotShapeProfile() throws {
        let reference = try date(2026, 7, 27, 12)
        let qualifying = try routineTransaction(
            amount: 210,
            date: dateInCompletedWeek(1, reference: reference)
        )
        let currentWeek = try routineTransaction(
            amount: 9_999,
            date: date(2026, 7, 28, 12)
        )
        let excluded = Transaction(
            amount: 8_000,
            date: try dateInCompletedWeek(2, reference: reference)
        )
        excluded.dailyBudgetOverride = false

        let rule = RecurringRule(
            title: "周期支出",
            amount: 500,
            nextDueDate: reference
        )
        let recurring = Transaction(
            amount: 500,
            date: try dateInCompletedWeek(3, reference: reference),
            recurringRule: rule
        )
        recurring.dailyBudgetOverride = true

        let profile = try XCTUnwrap(
            RoutineSpendingProfile.calculate(
                transactions: [qualifying, currentWeek, excluded, recurring],
                referenceDate: reference,
                calendar: calendar,
                lookbackDays: 90
            )
        )

        XCTAssertEqual(profile.observedWeekCount, 3)
        XCTAssertEqual(profile.qualifyingTransactionCount, 1)
        XCTAssertEqual(profile.weeklyTotals.sorted(), [0, 0, 210])
        XCTAssertEqual(profile.typicalDailyExpense, 0)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func routineTransaction(amount: Decimal, date: Date) -> Transaction {
        let transaction = Transaction(amount: amount, date: date)
        transaction.dailyBudgetOverride = true
        return transaction
    }

    private func dateInCompletedWeek(
        _ offset: Int,
        reference: Date
    ) throws -> Date {
        let referenceDay = calendar.startOfDay(for: reference)
        let weekStart = try XCTUnwrap(
            calendar.date(byAdding: .day, value: -(offset * 7), to: referenceDay)
        )
        return try XCTUnwrap(
            calendar.date(byAdding: .day, value: 2, to: weekStart)
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int
    ) throws -> Date {
        try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: year,
                    month: month,
                    day: day,
                    hour: hour
                )
            )
        )
    }
}
