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
    func testCoordinatorReservesUnmanagedCapacityAndClearsManagedRequestsAfterFailure() async throws {
        let unmanaged = UNNotificationRequest(
            identifier: "other.app.request",
            content: UNMutableNotificationContent(),
            trigger: nil
        )
        let center = FakeNotificationCenter(pending: [unmanaged], failAtAdd: 2)
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
            XCTAssertEqual(pending.map(\.identifier), ["other.app.request"])
            let status = NotificationScheduleStatusStore(userDefaults: defaults).load()
            XCTAssertEqual(status.capacity, 63)
            XCTAssertNotNil(status.errorMessage)
        }
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
    private let failAtAdd: Int?
    private var addCount = 0

    init(pending: [UNNotificationRequest] = [], failAtAdd: Int? = nil) {
        self.pending = pending
        self.failAtAdd = failAtAdd
    }

    func pendingRequests() async -> [UNNotificationRequest] {
        pending
    }

    func add(_ request: UNNotificationRequest) async throws {
        addCount += 1
        if addCount == failAtAdd {
            throw NSError(domain: "FakeNotificationCenter", code: 1)
        }
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(request)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) async {
        pending.removeAll { identifiers.contains($0.identifier) }
    }
}
