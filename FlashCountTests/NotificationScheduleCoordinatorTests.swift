import XCTest
import UserNotifications
@testable import FlashCount

final class NotificationScheduleCoordinatorTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testSelectionKeepsNearestCandidatesWithinCapacity() {
        let base = Date(timeIntervalSince1970: 1_000)
        let candidates = (0..<70).map { index in
            NotificationScheduleCandidate(
                identifier: "candidate.\(index)",
                kind: .report(period: .monthly),
                nextTriggerDate: base.addingTimeInterval(TimeInterval(index)),
                dateComponents: DateComponents(),
                repeats: false,
                title: "title",
                body: "body",
                interruption: .active
            )
        }

        let selection = NotificationScheduleSelection.make(candidates: candidates, capacity: 64)

        XCTAssertEqual(selection.selected.count, 64)
        XCTAssertEqual(selection.dropped.count, 6)
        XCTAssertEqual(selection.selected.last?.identifier, "candidate.63")
    }

    func testReminderMainTriggerWinsTieAgainstReport() {
        let date = Date(timeIntervalSince1970: 1_000)
        let reminderID = UUID()
        let reminder = NotificationScheduleCandidate(
            identifier: "reminder",
            kind: .reminder(id: reminderID, offsetIndex: 0),
            nextTriggerDate: date,
            dateComponents: DateComponents(),
            repeats: false,
            title: "r",
            body: "r",
            interruption: .active
        )
        let report = NotificationScheduleCandidate(
            identifier: "report",
            kind: .report(period: .daily),
            nextTriggerDate: date,
            dateComponents: DateComponents(),
            repeats: true,
            title: "p",
            body: "p",
            interruption: .active
        )

        XCTAssertEqual(
            NotificationScheduleSelection.make(candidates: [report, reminder], capacity: 1).selected.first?.identifier,
            "reminder"
        )
    }

    func testPlannerExpandsStrongReminderAndKeepsRepeatingReportsSingleSlot() throws {
        let reference = try date(2026, 7, 14, 8)
        let reminder = ReminderItem(
            title: "交费",
            dueDate: try date(2026, 7, 14, 9),
            intensity: .strong
        )
        let preferences = ReportReminderPreferences(
            enabledPeriods: [.daily, .weekly],
            deliveryTime: ReportReminderTime(hour: 10, minute: 0)
        )

        let candidates = NotificationSchedulePlanner.candidates(
            reminders: [reminder],
            reportPreferences: preferences,
            referenceDate: reference,
            calendar: calendar
        )

        XCTAssertEqual(candidates.filter { if case .reminder = $0.kind { return true }; return false }.count, 5)
        XCTAssertEqual(candidates.filter { if case .report = $0.kind { return true }; return false }.count, 2)
        XCTAssertTrue(candidates.filter { if case .report = $0.kind { return true }; return false }.allSatisfy(\.repeats))
    }

    func testReportPlannerProducesRequestedRollingWindowAndClampsLeapDay() throws {
        let preferences = ReportReminderPreferences(
            enabledPeriods: [.monthly, .yearly],
            deliveryTime: ReportReminderTime(hour: 8, minute: 0),
            monthlyDeliveryDay: 31,
            yearlyDeliveryMonth: 2,
            yearlyDeliveryDay: 29
        )
        let plans = ReportReminderSchedulePlanner.plans(
            for: preferences,
            referenceDate: try date(2027, 1, 30, 10),
            calendar: calendar,
            occurrenceLimit: 64
        )

        XCTAssertEqual(plans.filter { $0.period == .monthly }.count, 64)
        XCTAssertEqual(plans.filter { $0.period == .yearly }.count, 64)
        XCTAssertEqual(plans.first { $0.period == .yearly }?.dateComponents.day, 28)
    }

    @MainActor
    func testCoordinatorUsesExplicitReportPreferencesInsteadOfStoredLoader() async throws {
        let center = FakeNotificationCenter()
        let base = try date(2026, 7, 14, 8)
        let coordinator = NotificationScheduleCoordinator(
            center: center,
            preferencesLoader: { .default },
            now: { base },
            calendar: calendar
        )
        let explicit = ReportReminderPreferences(
            enabledPeriods: [.daily],
            deliveryTime: ReportReminderTime(hour: 10, minute: 0)
        )

        _ = try await coordinator.rebuild(
            reminders: [],
            reportPreferences: explicit
        )

        let pending = await center.pendingRequests()
        XCTAssertEqual(pending.map(\.identifier), ["flashcount.report.daily"])
    }

    @MainActor
    func testCoordinatorRestoresManagedScheduleWhenReplacementFails() async throws {
        let unmanaged = UNNotificationRequest(
            identifier: "other.app.request",
            content: UNMutableNotificationContent(),
            trigger: nil
        )
        let previousManaged = UNNotificationRequest(
            identifier: "flashcount.reminder.previous.0",
            content: UNMutableNotificationContent(),
            trigger: nil
        )
        let center = FakeNotificationCenter(pending: [unmanaged, previousManaged], failAtAdd: 2)
        let base = try date(2026, 7, 14, 8)
        let reminders = (0..<3).map { index in
            ReminderItem(
                title: "R\(index)",
                dueDate: base.addingTimeInterval(TimeInterval(3_600 + index)),
                intensity: .normal
            )
        }
        let suite = "NotificationScheduleTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = NotificationScheduleCoordinator(
            center: center,
            statusStore: NotificationScheduleStatusStore(userDefaults: defaults),
            reminderLoader: { reminders },
            preferencesLoader: { .default },
            now: { base },
            calendar: calendar
        )

        do {
            _ = try await coordinator.rebuild()
            XCTFail("Expected injected add failure")
        } catch {
            let pending = await center.pendingRequests()
            XCTAssertEqual(Set(pending.map(\.identifier)), Set(["other.app.request", previousManaged.identifier]))
            let status = NotificationScheduleStatusStore(userDefaults: defaults).load()
            XCTAssertEqual(status.capacity, 63)
            XCTAssertEqual(status.scheduledCount, 1)
            XCTAssertNotNil(status.errorMessage)
        }
    }

    @MainActor
    func testCoordinatorReportsPartialRestoreWhenRestorationAlsoFails() async throws {
        let unmanaged = UNNotificationRequest(
            identifier: "other.app.request",
            content: UNMutableNotificationContent(),
            trigger: nil
        )
        let previousManaged = UNNotificationRequest(
            identifier: "flashcount.reminder.previous.0",
            content: UNMutableNotificationContent(),
            trigger: nil
        )
        let center = FakeNotificationCenter(
            pending: [unmanaged, previousManaged],
            failAtAdds: [2, 3]
        )
        let base = try date(2026, 7, 14, 8)
        let reminders = [
            ReminderItem(
                title: "R0",
                dueDate: base.addingTimeInterval(3_600),
                intensity: .strong
            )
        ]
        let suite = "NotificationScheduleTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = NotificationScheduleCoordinator(
            center: center,
            statusStore: NotificationScheduleStatusStore(userDefaults: defaults),
            reminderLoader: { reminders },
            preferencesLoader: { .default },
            now: { base },
            calendar: calendar
        )

        do {
            _ = try await coordinator.rebuild()
            XCTFail("Expected injected add failure")
        } catch {
            let pending = await center.pendingRequests()
            XCTAssertEqual(Set(pending.map(\.identifier)), Set([unmanaged.identifier]))
            let status = NotificationScheduleStatusStore(userDefaults: defaults).load()
            XCTAssertEqual(status.scheduledCount, 0)
            XCTAssertTrue(status.errorMessage?.contains("仅恢复 0/1 条") == true)
        }
    }

    func testPlannerProducesSubscriptionRenewalCandidate() throws {
        let reference = try date(2026, 7, 1, 8)
        let item = SubscriptionRenewalItem(
            id: UUID(),
            name: "iCloud",
            nextRenewalDate: try date(2026, 7, 10, 9),
            remindBeforeDays: 3
        )

        let candidates = NotificationSchedulePlanner.candidates(
            reminders: [],
            reportPreferences: .default,
            subscriptionRenewals: [item],
            referenceDate: reference,
            calendar: calendar
        )

        let subscriptionCandidates = candidates.filter {
            if case .subscriptionRenewal = $0.kind { return true }
            return false
        }
        XCTAssertEqual(subscriptionCandidates.count, 1)
        let candidate = try XCTUnwrap(subscriptionCandidates.first)
        XCTAssertEqual(candidate.identifier, "flashcount.subscription.\(item.id.uuidString)")
        XCTAssertEqual(candidate.nextTriggerDate, try date(2026, 7, 7, 9), "续费前 3 天触发")
        XCTAssertFalse(candidate.repeats)
        XCTAssertEqual(candidate.sortPriority, 1)
        XCTAssertTrue(candidate.body.contains(item.name), "通知文案带订阅名称")
    }

    func testPlannerDropsSubscriptionsWithoutReminderOrPastFireDate() throws {
        let reference = try date(2026, 7, 1, 8)
        let noReminder = SubscriptionRenewalItem(
            id: UUID(),
            name: "不提醒",
            nextRenewalDate: try date(2026, 7, 10),
            remindBeforeDays: nil
        )
        let past = SubscriptionRenewalItem(
            id: UUID(),
            name: "已过触发",
            nextRenewalDate: try date(2026, 7, 3),
            remindBeforeDays: 3
        )

        let candidates = NotificationSchedulePlanner.candidates(
            reminders: [],
            reportPreferences: .default,
            subscriptionRenewals: [noReminder, past],
            referenceDate: reference,
            calendar: calendar
        )

        XCTAssertTrue(candidates.filter { if case .subscriptionRenewal = $0.kind { return true }; return false }.isEmpty)
    }

    @MainActor
    func testCoordinatorSchedulesSubscriptionFromInjectedLoader() async throws {
        let center = FakeNotificationCenter()
        let base = try date(2026, 7, 1, 8)
        let item = SubscriptionRenewalItem(
            id: UUID(),
            name: "Netflix",
            nextRenewalDate: try date(2026, 7, 10, 9),
            remindBeforeDays: 2
        )
        let coordinator = NotificationScheduleCoordinator(
            center: center,
            preferencesLoader: { .default },
            subscriptionLoader: { [item] },
            now: { base },
            calendar: calendar
        )

        _ = try await coordinator.rebuild(reminders: [])

        let pending = await center.pendingRequests()
        XCTAssertEqual(pending.map(\.identifier), ["flashcount.subscription.\(item.id.uuidString)"])
        let userInfo = pending.first?.content.userInfo
        XCTAssertEqual(
            userInfo?[SubscriptionRoute.notificationSubscriptionIDUserInfoKey] as? String,
            item.id.uuidString
        )
    }

    func testStatusDecodesLegacyPayloadWithoutSubscriptionField() throws {
        let json = """
        {"scheduledCount":2,"capacity":64,"unmanagedCount":0,
         "droppedReminderIDs":[],"droppedReportPeriods":[],
         "errorMessage":null,"updatedAt":"2026-07-01T00:00:00Z"}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let status = try decoder.decode(NotificationScheduleStatus.self, from: json)
        XCTAssertEqual(status.droppedSubscriptionIDs, [])
        XCTAssertEqual(status.scheduledCount, 2)
        XCTAssertFalse(status.hasDroppedCandidates)
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0
    ) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }
}

private actor FakeNotificationCenter: NotificationCenterScheduling {
    private var pending: [UNNotificationRequest]
    private let failAtAdds: Set<Int>
    private var addCount = 0

    init(
        pending: [UNNotificationRequest] = [],
        failAtAdd: Int? = nil,
        failAtAdds: Set<Int> = []
    ) {
        self.pending = pending
        self.failAtAdds = failAtAdds.union(failAtAdd.map { [$0] } ?? [])
    }

    func pendingRequests() async -> [UNNotificationRequest] {
        pending
    }

    func supportsTimeSensitiveNotifications() async -> Bool {
        false
    }

    func add(_ request: UNNotificationRequest) async throws {
        addCount += 1
        if failAtAdds.contains(addCount) {
            throw NSError(domain: "FakeNotificationCenter", code: 1)
        }
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(request)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) async {
        pending.removeAll { identifiers.contains($0.identifier) }
    }
}
