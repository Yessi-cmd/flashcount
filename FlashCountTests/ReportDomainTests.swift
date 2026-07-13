import XCTest
import SwiftData
@testable import FlashCount

@MainActor
final class ReportDomainTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testDailyScheduledTargetUsesMidnightThroughTriggerAndAlignedComparison() throws {
        let trigger = try date(2026, 7, 12, 20, 15)
        let selection = ReportPeriodCalculator(calendar: calendar).selection(
            for: .daily,
            target: .scheduled(period: .daily, triggerDate: trigger)
        )

        XCTAssertEqual(selection.reportRange.start, try date(2026, 7, 12))
        XCTAssertEqual(selection.reportRange.end, trigger)
        XCTAssertEqual(selection.comparisonRange.start, try date(2026, 7, 11))
        XCTAssertEqual(selection.comparisonRange.end, try date(2026, 7, 11, 20, 15))
    }

    func testCompletePeriodsUseMondayWeekStartAndPreviousCalendarPeriods() throws {
        let trigger = try date(2026, 7, 15, 9)
        let calculator = ReportPeriodCalculator(calendar: calendar)

        let week = calculator.selection(for: .weekly, target: .scheduled(period: .weekly, triggerDate: trigger))
        XCTAssertEqual(week.reportRange, ReportDateRange(start: try date(2026, 7, 6), end: try date(2026, 7, 13)))
        XCTAssertEqual(week.comparisonRange, ReportDateRange(start: try date(2026, 6, 29), end: try date(2026, 7, 6)))

        let month = calculator.selection(for: .monthly, target: .scheduled(period: .monthly, triggerDate: trigger))
        XCTAssertEqual(month.reportRange, ReportDateRange(start: try date(2026, 6, 1), end: try date(2026, 7, 1)))
        XCTAssertEqual(month.comparisonRange, ReportDateRange(start: try date(2026, 5, 1), end: try date(2026, 6, 1)))

        let year = calculator.selection(for: .yearly, target: .scheduled(period: .yearly, triggerDate: trigger))
        XCTAssertEqual(year.reportRange, ReportDateRange(start: try date(2025, 1, 1), end: try date(2026, 1, 1)))
        XCTAssertEqual(year.comparisonRange, ReportDateRange(start: try date(2024, 1, 1), end: try date(2025, 1, 1)))
    }

    func testCurrentPeriodComparisonUsesSameElapsedPortion() throws {
        let reference = try date(2026, 7, 12, 12)
        let selection = ReportPeriodCalculator(calendar: calendar).selection(
            for: .monthly,
            target: .current(referenceDate: reference)
        )

        XCTAssertEqual(selection.reportRange, ReportDateRange(start: try date(2026, 7, 1), end: reference))
        XCTAssertEqual(selection.comparisonRange, ReportDateRange(start: try date(2026, 6, 1), end: try date(2026, 6, 12, 12)))
    }

    func testTypedBucketGranularitiesAndCounts() throws {
        let calculator = ReportPeriodCalculator(calendar: calendar)
        let trigger = try date(2026, 7, 15, 9)

        let daily = calculator.selection(for: .daily, target: .current(referenceDate: try date(2026, 7, 15, 9, 30)))
        XCTAssertEqual(calculator.bucketRanges(for: daily).count, 10)
        XCTAssertEqual(daily.period.bucketGranularity, .hour)

        let weekly = calculator.selection(for: .weekly, target: .scheduled(period: .weekly, triggerDate: trigger))
        XCTAssertEqual(calculator.bucketRanges(for: weekly).count, 7)
        XCTAssertEqual(weekly.period.bucketGranularity, .day)

        let monthly = calculator.selection(for: .monthly, target: .scheduled(period: .monthly, triggerDate: trigger))
        XCTAssertEqual(calculator.bucketRanges(for: monthly).count, 5)
        XCTAssertEqual(monthly.period.bucketGranularity, .week)

        let yearly = calculator.selection(for: .yearly, target: .scheduled(period: .yearly, triggerDate: trigger))
        XCTAssertEqual(calculator.bucketRanges(for: yearly).count, 12)
        XCTAssertEqual(yearly.period.bucketGranularity, .month)
    }

    func testReportServiceUsesHalfOpenTargetAndAlignedComparison() throws {
        let context = try makeContext()
        let reference = try date(2026, 7, 12, 12)
        insertExpense(100, at: try date(2026, 7, 2), into: context)
        insertExpense(50, at: reference, into: context)
        insertExpense(50, at: try date(2026, 6, 2), into: context)
        insertExpense(1_000, at: try date(2026, 6, 20), into: context)
        try context.save()

        let report = try ReportService(modelContext: context, calendar: calendar).generateReport(
            period: .monthly,
            target: .current(referenceDate: reference)
        )

        XCTAssertEqual(report.totalExpense, 100)
        XCTAssertEqual(report.expenseChange, 1)
        XCTAssertEqual(report.timeBuckets.reduce(Decimal.zero) { $0 + $1.expense }, 100)
        XCTAssertEqual(report.dailyExpenses.count, report.timeBuckets.count)
    }

    func testScheduledWeeklyReportAggregatesDaysAndComparesCompletePriorWeek() throws {
        let context = try makeContext()
        let trigger = try date(2026, 7, 15, 9)
        insertExpense(10, at: try date(2026, 7, 6), into: context)
        insertExpense(20, at: try date(2026, 7, 12, 23, 59), into: context)
        insertExpense(999, at: try date(2026, 7, 13), into: context)
        insertExpense(15, at: try date(2026, 6, 30), into: context)
        try context.save()

        let report = try ReportService(modelContext: context, calendar: calendar).generateReport(
            period: .weekly,
            target: .scheduled(period: .weekly, triggerDate: trigger)
        )

        XCTAssertEqual(report.totalExpense, 30)
        XCTAssertEqual(report.expenseChange, 1)
        XCTAssertEqual(report.timeBuckets.count, 7)
        XCTAssertTrue(report.timeBuckets.allSatisfy { $0.granularity == .day })
        XCTAssertEqual(report.timeBuckets.map(\.expense), [10, 0, 0, 0, 0, 0, 20])
    }

    func testReminderPreferencesRoundTripAndCorruptionFallback() {
        let suiteName = "ReportDomainTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "preferences"
        let store = UserDefaultsReportReminderPreferencesStore(userDefaults: defaults, key: key)
        let preferences = ReportReminderPreferences(
            enabledPeriods: Set(ReportPeriod.allCases),
            deliveryTime: ReportReminderTime(hour: 8, minute: 45),
            weeklyDeliveryWeekday: 2,
            monthlyDeliveryDay: 31,
            yearlyDeliveryMonth: 12,
            yearlyDeliveryDay: 31
        )

        XCTAssertEqual(store.load(), .default)
        XCTAssertNoThrow(try store.save(preferences))
        XCTAssertEqual(store.load(), preferences)

        defaults.set(Data("invalid".utf8), forKey: key)
        XCTAssertEqual(store.load(), .default)
        XCTAssertEqual(defaults.data(forKey: key), Data("invalid".utf8))
    }

    func testReminderPreferencesNormalizePersistedValues() throws {
        let suiteName = "ReportDomainTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "preferences"
        defaults.set(Data("""
        {"enabledPeriods":["日报"],"deliveryTime":{"hour":99,"minute":-5},"weeklyDeliveryWeekday":9,"monthlyDeliveryDay":0,"yearlyDeliveryMonth":13,"yearlyDeliveryDay":99}
        """.utf8), forKey: key)

        let loaded = UserDefaultsReportReminderPreferencesStore(userDefaults: defaults, key: key).load()
        XCTAssertEqual(loaded.deliveryTime, ReportReminderTime(hour: 23, minute: 0))
        XCTAssertEqual(loaded.weeklyDeliveryWeekday, 7)
        XCTAssertEqual(loaded.monthlyDeliveryDay, 1)
        XCTAssertEqual(loaded.yearlyDeliveryMonth, 12)
        XCTAssertEqual(loaded.yearlyDeliveryDay, 31)
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0
    ) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )))
    }

    private func insertExpense(_ amount: Decimal, at date: Date, into context: ModelContext) {
        context.insert(Transaction(amount: amount, date: date))
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Transaction.self,
            Category.self,
            Ledger.self,
            RecurringRule.self,
            Budget.self,
            Asset.self,
            PhysicalAsset.self,
            CashPoolItem.self,
            CashPoolState.self,
            SavingsGoal.self,
            InstallmentBill.self,
            TransactionTemplate.self,
            configurations: configuration
        )
        return ModelContext(container)
    }
}
