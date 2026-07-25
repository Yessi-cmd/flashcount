import SwiftData
import XCTest
@testable import FlashCount

@MainActor
final class CashFlowForecastTests: XCTestCase {
    func testRecurringBackfillGeneratesTransactionAndIsIdempotent() throws {
        let context = try makeContext()
        let dueDate = try date(year: 2026, month: 7, day: 20, hour: 9)
        let now = try date(year: 2026, month: 7, day: 23, hour: 12)
        let ledger = Ledger(name: "生活", icon: "house.fill", colorHex: "#4E766A", isDefault: true)
        let rule = RecurringRule(
            title: "订阅",
            amount: 50,
            frequency: .weekly,
            nextDueDate: dueDate,
            ledger: ledger
        )
        context.insert(ledger)
        context.insert(rule)
        try context.save()

        let service = RecurringOccurrenceService(modelContext: context, calendar: calendar)
        let previews = service.pendingOccurrences(
            rules: [rule],
            now: now,
            maxOccurrences: 10
        )
        XCTAssertEqual(previews.count, 1)

        let result = try service.resolve([
            RecurringBackfillSelection(occurrenceKey: previews[0].id, action: .generate)
        ], now: now)
        XCTAssertEqual(result.generatedCount, 1)
        XCTAssertEqual(result.cashPoolDelta, -50)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Transaction>()).count, 1)
        XCTAssertEqual(rule.nextDueDate, try date(year: 2026, month: 7, day: 27, hour: 9))

        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<CashPoolState>()).first)
        XCTAssertEqual(state.transactionDelta, -50)

        let secondPreview = service.pendingOccurrences(
            rules: [rule],
            occurrences: try context.fetch(FetchDescriptor<RecurringOccurrence>()),
            now: now,
            maxOccurrences: 10
        )
        XCTAssertTrue(secondPreview.isEmpty)
        let duplicateResult = try service.resolve([
            RecurringBackfillSelection(occurrenceKey: previews[0].id, action: .generate)
        ], now: now)
        XCTAssertEqual(duplicateResult.generatedCount, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Transaction>()).count, 1)
    }

    func testSkippedBackfillAdvancesCursorWithoutChangingCashPool() throws {
        let context = try makeContext()
        let dueDate = try date(year: 2026, month: 7, day: 1)
        let now = try date(year: 2026, month: 7, day: 3)
        let rule = RecurringRule(
            title: "月租",
            amount: 1_200,
            frequency: .monthly,
            nextDueDate: dueDate
        )
        context.insert(rule)
        try context.save()

        let service = RecurringOccurrenceService(modelContext: context, calendar: calendar)
        let preview = try XCTUnwrap(service.pendingOccurrences(rules: [rule], now: now).first)
        let result = try service.resolve([
            RecurringBackfillSelection(occurrenceKey: preview.id, action: .skip)
        ], now: now)

        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Transaction>()).count, 0)
        XCTAssertEqual(rule.nextDueDate, try date(year: 2026, month: 8, day: 1))
        XCTAssertEqual(try context.fetch(FetchDescriptor<RecurringOccurrence>()).first?.status, .skipped)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CashPoolState>()).count, 0)
    }

    func testForecastIncludesRecurringAndInstallmentEventsWithoutWritingData() throws {
        let context = try makeContext()
        let referenceDate = try date(year: 2026, month: 7, day: 25, hour: 12)
        let recurringDate = try date(year: 2026, month: 8, day: 1)
        let installmentDate = try date(year: 2026, month: 8, day: 5)
        let item = CashPoolItem(name: "银行卡", kind: .cash, amount: 1_000)
        let rule = RecurringRule(
            title: "会员",
            amount: 100,
            frequency: .monthly,
            nextDueDate: recurringDate
        )
        let bill = InstallmentBill(
            name: "手机分期",
            totalAmount: 90,
            installmentCount: 1,
            repaymentDay: 5,
            firstRepaymentDate: installmentDate
        )
        context.insert(item)
        context.insert(rule)
        context.insert(bill)
        try context.save()

        let forecast = CashFlowForecastService.forecast(
            cashPoolItems: [item],
            cashPoolState: nil,
            recurringRules: [rule],
            occurrences: [],
            installmentBills: [bill],
            transactions: [],
            referenceDate: referenceDate,
            horizon: .thirtyDays,
            mode: .fixedOnly,
            calendar: calendar
        )

        XCTAssertEqual(forecast.openingBalance, 1_000)
        XCTAssertEqual(forecast.confirmedExpense, 190)
        XCTAssertEqual(forecast.endingBalance, 810)
        XCTAssertEqual(forecast.events.count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Transaction>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CashPoolState>()).count, 0)
    }

    func testForecastDoesNotRepeatResolvedRecurringOccurrence() throws {
        let referenceDate = try date(year: 2026, month: 7, day: 25, hour: 12)
        let scheduledDate = try date(year: 2026, month: 8, day: 1)
        let rule = RecurringRule(title: "会员", amount: 100, nextDueDate: scheduledDate)
        let occurrence = RecurringOccurrence(
            occurrenceKey: RecurringOccurrence.key(ruleID: rule.id, scheduledDate: scheduledDate, calendar: calendar),
            ruleID: rule.id,
            scheduledDate: scheduledDate,
            amount: 100,
            isExpense: true,
            title: "会员",
            status: .generated
        )

        let forecast = CashFlowForecastService.forecast(
            cashPoolItems: [],
            cashPoolState: nil,
            recurringRules: [rule],
            occurrences: [occurrence],
            installmentBills: [],
            transactions: [],
            referenceDate: referenceDate,
            horizon: .thirtyDays,
            mode: .fixedOnly,
            calendar: calendar
        )

        XCTAssertTrue(forecast.events.isEmpty)
        XCTAssertEqual(forecast.endingBalance, 0)
    }

    func testInstallmentPaymentRemainderMatchesTotalAmount() {
        let bill = InstallmentBill(
            name: "设备",
            totalAmount: 100,
            installmentCount: 3,
            repaymentDay: 1,
            firstRepaymentDate: .now
        )
        let total = (0..<bill.normalizedInstallmentCount)
            .reduce(Decimal.zero) { $0 + bill.paymentAmount(forInstallment: $1) }
        XCTAssertEqual(total, 100)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Transaction.self,
            Category.self,
            Ledger.self,
            RecurringRule.self,
            RecurringOccurrence.self,
            CashPoolItem.self,
            CashPoolState.self,
            InstallmentBill.self,
            configurations: configuration
        )
        return ModelContext(container)
    }
}
