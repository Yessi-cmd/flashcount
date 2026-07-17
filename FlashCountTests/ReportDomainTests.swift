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

    func testPayCycleUsesConfiguredPaydayForCurrentCompletedAndMonthEndRanges() throws {
        let calculator = ReportPeriodCalculator(calendar: calendar, payday: 25)
        let reference = try date(2026, 7, 15, 12)
        let current = calculator.selection(for: .payCycle, target: .current(referenceDate: reference))

        XCTAssertEqual(current.reportRange, ReportDateRange(start: try date(2026, 6, 25), end: reference))
        XCTAssertEqual(current.comparisonRange, ReportDateRange(start: try date(2026, 5, 25), end: try date(2026, 6, 14, 12)))

        let scheduled = calculator.selection(
            for: .payCycle,
            target: .scheduled(period: .payCycle, triggerDate: try date(2026, 7, 25, 9))
        )
        XCTAssertEqual(scheduled.reportRange, ReportDateRange(start: try date(2026, 6, 25), end: try date(2026, 7, 25)))
        XCTAssertEqual(scheduled.comparisonRange, ReportDateRange(start: try date(2026, 5, 25), end: try date(2026, 6, 25)))

        let monthEnd = ReportPeriodCalculator(calendar: calendar, payday: 31).selection(
            for: .payCycle,
            target: .scheduled(period: .payCycle, triggerDate: try date(2027, 2, 28, 9))
        )
        XCTAssertEqual(monthEnd.reportRange, ReportDateRange(start: try date(2027, 1, 31), end: try date(2027, 2, 28)))
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

        let payCycleCalculator = ReportPeriodCalculator(calendar: calendar, payday: 25)
        let payCycle = payCycleCalculator.selection(
            for: .payCycle,
            target: .scheduled(period: .payCycle, triggerDate: try date(2026, 7, 25, 9))
        )
        XCTAssertEqual(payCycleCalculator.bucketRanges(for: payCycle).count, 30)
        XCTAssertEqual(payCycle.period.bucketGranularity, .day)
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
        XCTAssertEqual(report.transactionCount, 1)
        XCTAssertEqual(report.smartAnalysis.averageLabel, "天均支出")
        XCTAssertNotNil(report.smartAnalysis.projectedExpense)
    }

    func testSmartAnalysisAdaptsMetricsAndPeakInsightToDailyReport() throws {
        let context = try makeContext()
        let reference = try date(2026, 7, 12, 20)
        insertExpense(20, at: try date(2026, 7, 12, 9), into: context)
        insertExpense(80, at: try date(2026, 7, 12, 18), into: context)
        try context.save()

        let report = try ReportService(modelContext: context, calendar: calendar).generateReport(
            period: .daily,
            target: .current(referenceDate: reference)
        )

        XCTAssertEqual(report.smartAnalysis.averageLabel, "笔均支出")
        XCTAssertEqual(report.smartAnalysis.averageExpense, 50)
        XCTAssertEqual(report.smartAnalysis.activeBucketCount, 2)
        XCTAssertEqual(report.smartAnalysis.peakBucket?.expense, 80)
        XCTAssertEqual(report.smartAnalysis.insights.first?.id, "period-peak")
        XCTAssertEqual(report.smartAnalysis.insights.first?.title, "今日高峰时段")
    }

    func testSmartAnalysisDetectsWeekendConcentrationAndSensitiveSavingsRate() throws {
        let context = try makeContext()
        insertExpense(90, at: try date(2026, 7, 11, 12), into: context)
        insertExpense(10, at: try date(2026, 7, 8, 12), into: context)
        context.insert(Transaction(amount: 200, isExpense: false, date: try date(2026, 7, 7, 12)))
        try context.save()

        let report = try ReportService(modelContext: context, calendar: calendar).generateReport(
            period: .weekly,
            target: .completed(containing: try date(2026, 7, 8))
        )

        XCTAssertEqual(report.smartAnalysis.savingsRate, 0.5)
        XCTAssertTrue(report.smartAnalysis.insights.contains { $0.id == "weekend-share" })
        XCTAssertEqual(report.smartAnalysis.insights.first(where: { $0.id == "savings-rate" })?.isSensitive, true)
        XCTAssertNil(report.smartAnalysis.projectedExpense)
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

    func testScheduledPayCycleReportAggregatesConfiguredCycleAndComparison() throws {
        let context = try makeContext()
        insertExpense(100, at: try date(2026, 6, 25), into: context)
        insertExpense(50, at: try date(2026, 7, 24, 23, 59), into: context)
        insertExpense(999, at: try date(2026, 7, 25), into: context)
        insertExpense(75, at: try date(2026, 5, 25), into: context)
        try context.save()

        let report = try ReportService(modelContext: context, calendar: calendar, payday: 25).generateReport(
            period: .payCycle,
            target: .scheduled(period: .payCycle, triggerDate: try date(2026, 7, 25, 9))
        )

        XCTAssertEqual(report.reportRange, ReportDateRange(start: try date(2026, 6, 25), end: try date(2026, 7, 25)))
        XCTAssertEqual(report.totalExpense, 150)
        XCTAssertEqual(report.expenseChange, 1)
        XCTAssertEqual(report.timeBuckets.count, 30)
        XCTAssertEqual(report.timeBuckets.reduce(Decimal.zero) { $0 + $1.expense }, 150)
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

    func testReportReminderPlannerUsesRepeatingDailyAndWeeklyTriggers() {
        let preferences = ReportReminderPreferences(
            enabledPeriods: [.daily, .weekly],
            deliveryTime: ReportReminderTime(hour: 8, minute: 45),
            weeklyDeliveryWeekday: 6
        )

        let plans = ReportReminderSchedulePlanner.plans(
            for: preferences,
            referenceDate: Date(timeIntervalSince1970: 0),
            calendar: calendar
        )

        XCTAssertEqual(plans.count, 2)
        XCTAssertEqual(plans.first(where: { $0.period == .daily })?.dateComponents.hour, 8)
        XCTAssertEqual(plans.first(where: { $0.period == .daily })?.dateComponents.minute, 45)
        XCTAssertEqual(plans.first(where: { $0.period == .daily })?.repeats, true)
        XCTAssertEqual(plans.first(where: { $0.period == .weekly })?.dateComponents.weekday, 6)
        XCTAssertEqual(plans.first(where: { $0.period == .weekly })?.repeats, true)
    }

    func testReportReminderPlannerClampsMonthEndAndLeapDay() throws {
        let reference = try date(2027, 1, 30, 10)
        let preferences = ReportReminderPreferences(
            enabledPeriods: [.monthly, .yearly],
            deliveryTime: ReportReminderTime(hour: 8, minute: 45),
            monthlyDeliveryDay: 31,
            yearlyDeliveryMonth: 2,
            yearlyDeliveryDay: 29
        )

        let plans = ReportReminderSchedulePlanner.plans(
            for: preferences,
            referenceDate: reference,
            calendar: calendar
        )
        let monthly = plans.filter { $0.period == .monthly }
        let yearly = plans.filter { $0.period == .yearly }

        XCTAssertEqual(monthly.count, 12)
        XCTAssertEqual(monthly[0].dateComponents.day, 31)
        XCTAssertEqual(monthly[0].dateComponents.month, 1)
        XCTAssertEqual(monthly[1].dateComponents.day, 28)
        XCTAssertEqual(monthly[1].dateComponents.month, 2)
        XCTAssertEqual(yearly[0].dateComponents.year, 2027)
        XCTAssertEqual(yearly[0].dateComponents.day, 28)
        XCTAssertEqual(yearly[1].dateComponents.year, 2028)
        XCTAssertEqual(yearly[1].dateComponents.day, 29)
    }

    func testPayCycleReminderUsesConfiguredPaydayAndClampsMonthEnd() throws {
        let preferences = ReportReminderPreferences(
            enabledPeriods: [.payCycle],
            deliveryTime: ReportReminderTime(hour: 20, minute: 30)
        )

        let plans = ReportReminderSchedulePlanner.plans(
            for: preferences,
            referenceDate: try date(2027, 1, 30, 10),
            calendar: calendar,
            payday: 31
        )

        XCTAssertEqual(plans.count, 12)
        XCTAssertEqual(plans[0].period, .payCycle)
        XCTAssertEqual(plans[0].dateComponents.month, 1)
        XCTAssertEqual(plans[0].dateComponents.day, 31)
        XCTAssertEqual(plans[0].dateComponents.hour, 20)
        XCTAssertEqual(plans[1].dateComponents.month, 2)
        XCTAssertEqual(plans[1].dateComponents.day, 28)
        XCTAssertTrue(plans.allSatisfy { !$0.repeats })
    }

    func testCompletedTargetSelectsContainingCalendarPeriodAndNavigatesTowardCurrent() throws {
        let calculator = ReportPeriodCalculator(calendar: calendar)
        let anchor = try date(2026, 6, 15)
        let current = try date(2026, 7, 15)
        let selection = calculator.selection(for: .monthly, target: .completed(containing: anchor))

        XCTAssertEqual(selection.reportRange, ReportDateRange(start: try date(2026, 6, 1), end: try date(2026, 7, 1)))
        XCTAssertNil(calculator.nextCompletedAnchor(for: selection, referenceDate: current))
        XCTAssertEqual(calculator.previousCompletedAnchor(for: selection), try date(2026, 5, 1))
    }

    func testReportFormatterIncludesNonMidnightEndDateAndFormatsPercentages() throws {
        let formatter = ReportDateRangeFormatter(calendar: calendar)
        let range = ReportDateRange(start: try date(2026, 7, 6), end: try date(2026, 7, 12, 12))

        XCTAssertEqual(formatter.bucketLabel(for: range, granularity: .week), "7月6日–7月12日")
        XCTAssertEqual(ReportPercentageFormatter.categoryShare(1), "100%")
        XCTAssertEqual(ReportPercentageFormatter.changeRate(1), "100%")
        XCTAssertEqual(ReportPercentageFormatter.changeRate(1.5), "100%+")
        XCTAssertEqual(ReportChangePresentation.make(change: 0.5, metric: .income).isFavorable, true)
        XCTAssertEqual(ReportChangePresentation.make(change: 0.5, metric: .expense).isFavorable, false)
    }

    func testScheduledStreakStopsAtReportExclusiveEnd() throws {
        let context = try makeContext()
        let trigger = try date(2026, 7, 15, 9)
        insertExpense(10, at: try date(2026, 7, 11, 10), into: context)
        insertExpense(10, at: try date(2026, 7, 12, 10), into: context)
        insertExpense(10, at: try date(2026, 7, 13, 10), into: context)
        try context.save()

        let report = try ReportService(modelContext: context, calendar: calendar).generateReport(
            period: .weekly,
            target: .scheduled(period: .weekly, triggerDate: trigger)
        )

        XCTAssertEqual(report.streakDays, 2)
    }

    func testReportBudgetSnapshotUsesReportEndPayCycleAndExcludesLaterSpending() throws {
        let reportEnd = try date(2026, 7, 1)
        let reportRange = ReportDateRange(start: try date(2026, 6, 1), end: reportEnd)
        let cycle = PayCycleService.cycle(containing: try date(2026, 6, 30), payday: 25, calendar: calendar)
        let budget = Budget(
            monthlyLimit: 1_000,
            year: calendar.component(.year, from: cycle.start),
            month: calendar.component(.month, from: cycle.start)
        )
        let category = Category(
            name: "餐饮",
            icon: "fork.knife",
            colorHex: "#FF0000",
            defaultKey: Category.defaultKey(for: "餐饮", isExpense: true)
        )
        let included = Transaction(amount: 100, date: try date(2026, 6, 30, 12), category: category)
        let later = Transaction(amount: 900, date: try date(2026, 7, 2), category: category)

        let snapshot = ReportBudgetSnapshotService.snapshot(
            budgets: [budget],
            transactions: [included, later],
            reportRange: reportRange,
            target: .completed(containing: try date(2026, 6, 15)),
            payday: 25,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.budget?.id, budget.id)
        XCTAssertEqual(snapshot.analysis?.totalSpent, 100)
        XCTAssertEqual(snapshot.cutoff, reportEnd)
    }

    func testReportRoutePersistsColdLaunchDestination() {
        let suiteName = "ReportRouteTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        ReportRoute.requestScheduled(
            period: .monthly,
            deliveredAt: Date(timeIntervalSince1970: 123),
            userDefaults: defaults
        )

        XCTAssertTrue(defaults.bool(forKey: ReportRoute.requestKey))
        XCTAssertEqual(defaults.string(forKey: ReportRoute.periodKey), ReportPeriod.monthly.rawValue)
        let request = ReportRoute.consume(userDefaults: defaults)
        XCTAssertEqual(request?.period, .monthly)
        XCTAssertEqual(request?.target, .scheduled(deliveredAt: Date(timeIntervalSince1970: 123)))
        XCTAssertNil(defaults.data(forKey: ReportRoute.payloadKey))
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
