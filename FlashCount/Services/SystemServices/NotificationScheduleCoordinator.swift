import Foundation
import UserNotifications

enum NotificationCandidateKind: Equatable {
    case reminder(id: UUID, offsetIndex: Int)
    case report(period: ReportPeriod)
}

enum NotificationInterruptionKind: Equatable {
    case active
    case timeSensitive
}

struct NotificationScheduleCandidate: Equatable {
    let identifier: String
    let kind: NotificationCandidateKind
    let nextTriggerDate: Date
    let dateComponents: DateComponents
    let repeats: Bool
    let title: String
    let body: String
    let interruption: NotificationInterruptionKind

    var sortPriority: Int {
        switch kind {
        case .reminder(_, let index): return index == 0 ? 0 : 1
        case .report: return 2
        }
    }
}

struct NotificationScheduleSelection: Equatable {
    let selected: [NotificationScheduleCandidate]
    let dropped: [NotificationScheduleCandidate]
    let capacity: Int

    static func make(
        candidates: [NotificationScheduleCandidate],
        capacity: Int
    ) -> NotificationScheduleSelection {
        let sorted = candidates.sorted {
            if $0.nextTriggerDate != $1.nextTriggerDate {
                return $0.nextTriggerDate < $1.nextTriggerDate
            }
            if $0.sortPriority != $1.sortPriority {
                return $0.sortPriority < $1.sortPriority
            }
            return $0.identifier < $1.identifier
        }
        let safeCapacity = max(capacity, 0)
        return NotificationScheduleSelection(
            selected: Array(sorted.prefix(safeCapacity)),
            dropped: Array(sorted.dropFirst(safeCapacity)),
            capacity: safeCapacity
        )
    }
}

enum NotificationSchedulePlanner {
    static let maximumPendingRequests = 64
    static let reminderIdentifierPrefix = "flashcount.reminder."
    static let reportIdentifierPrefix = ReportReminderSchedulePlanner.identifierPrefix

    static func candidates(
        reminders: [ReminderItem],
        reportPreferences: ReportReminderPreferences,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        payday: Int = 1,
        includeReminderDetails: Bool = false
    ) -> [NotificationScheduleCandidate] {
        reminderCandidates(
            reminders: reminders,
            referenceDate: referenceDate,
            calendar: calendar,
            includeDetails: includeReminderDetails
        )
            + reportCandidates(
                preferences: reportPreferences,
                referenceDate: referenceDate,
                calendar: calendar,
                payday: payday
            )
    }

    static func isManaged(identifier: String) -> Bool {
        identifier.hasPrefix(reminderIdentifierPrefix)
            || identifier.hasPrefix(reportIdentifierPrefix)
    }

    private static func reminderCandidates(
        reminders: [ReminderItem],
        referenceDate: Date,
        calendar: Calendar,
        includeDetails: Bool
    ) -> [NotificationScheduleCandidate] {
        reminders
            .filter { !$0.isCompleted }
            .flatMap { reminder in
                reminder.intensity.notificationOffsets.enumerated().compactMap { index, offset in
                    let fireDate = reminder.dueDate.addingTimeInterval(offset)
                    guard fireDate > referenceDate else { return nil }
                    return NotificationScheduleCandidate(
                        identifier: "\(reminderIdentifierPrefix)\(reminder.id.uuidString).\(index)",
                        kind: .reminder(id: reminder.id, offsetIndex: index),
                        nextTriggerDate: fireDate,
                        dateComponents: calendar.dateComponents(
                            [.year, .month, .day, .hour, .minute],
                            from: fireDate
                        ),
                        repeats: false,
                        title: includeDetails ? reminder.title : "FlashCount 提醒",
                        body: includeDetails
                            ? (reminder.note.isEmpty ? reminderBody(for: reminder, index: index) : reminder.note)
                            : genericReminderBody(for: reminder, index: index),
                        interruption: reminder.intensity == .strong ? .timeSensitive : .active
                    )
                }
            }
    }

    private static func reportCandidates(
        preferences: ReportReminderPreferences,
        referenceDate: Date,
        calendar: Calendar,
        payday: Int
    ) -> [NotificationScheduleCandidate] {
        ReportReminderSchedulePlanner.plans(
            for: preferences,
            referenceDate: referenceDate,
            calendar: calendar,
            occurrenceLimit: maximumPendingRequests,
            payday: payday
        ).map { plan in
            NotificationScheduleCandidate(
                identifier: plan.identifier,
                kind: .report(period: plan.period),
                nextTriggerDate: plan.nextTriggerDate,
                dateComponents: plan.dateComponents,
                repeats: plan.repeats,
                title: plan.title,
                body: plan.body,
                interruption: .active
            )
        }
    }

    private static func reminderBody(for reminder: ReminderItem, index: Int) -> String {
        if reminder.intensity == .strong && index > 0 {
            return "还没有标记完成，记得处理这件事。"
        }
        return "到时间了，打开 FlashCount 标记完成。"
    }

    private static func genericReminderBody(for reminder: ReminderItem, index: Int) -> String {
        if reminder.intensity == .strong && index > 0 {
            return "你有一条待处理提醒，打开 FlashCount 标记完成。"
        }
        return "你有一条待处理提醒，打开 FlashCount 查看。"
    }
}

struct NotificationScheduleStatus: Codable, Equatable {
    let scheduledCount: Int
    let capacity: Int
    let unmanagedCount: Int
    let droppedReminderIDs: [UUID]
    let droppedReportPeriods: [ReportPeriod]
    let errorMessage: String?
    let updatedAt: Date

    static let empty = NotificationScheduleStatus(
        scheduledCount: 0,
        capacity: NotificationSchedulePlanner.maximumPendingRequests,
        unmanagedCount: 0,
        droppedReminderIDs: [],
        droppedReportPeriods: [],
        errorMessage: nil,
        updatedAt: .distantPast
    )

    var hasDroppedCandidates: Bool {
        !droppedReminderIDs.isEmpty || !droppedReportPeriods.isEmpty
    }

    var summary: String? {
        if let errorMessage {
            return "设置已保存，但通知安排失败：\(errorMessage)"
        }
        if hasDroppedCandidates {
            return "部分远期通知暂未安排。系统将优先保留最近到期的 \(scheduledCount) 条，打开 App 后会继续补排。"
        }
        return nil
    }
}

struct NotificationScheduleStatusStore {
    static let key = "notificationScheduleStatus.v1"

    let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> NotificationScheduleStatus {
        guard let data = userDefaults.data(forKey: Self.key),
              let status = try? decoder.decode(NotificationScheduleStatus.self, from: data) else {
            return .empty
        }
        return status
    }

    func save(_ status: NotificationScheduleStatus) {
        guard let data = try? encoder.encode(status) else { return }
        userDefaults.set(data, forKey: Self.key)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

protocol NotificationCenterScheduling: Sendable {
    func pendingRequests() async -> [UNNotificationRequest]
    func supportsTimeSensitiveNotifications() async -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingRequests(withIdentifiers identifiers: [String]) async
}

struct SystemNotificationCenterScheduler: NotificationCenterScheduling {
    func pendingRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    func supportsTimeSensitiveNotifications() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.timeSensitiveSetting == .enabled)
            }
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

actor NotificationScheduleCoordinator {
    static let shared = NotificationScheduleCoordinator()

    private let center: any NotificationCenterScheduling
    private let statusStore: NotificationScheduleStatusStore
    private let reminderLoader: @Sendable () -> [ReminderItem]
    private let preferencesLoader: @Sendable () -> ReportReminderPreferences
    private let reminderDetailsLoader: @Sendable () -> Bool
    private let paydayLoader: @Sendable () -> Int
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(
        center: any NotificationCenterScheduling = SystemNotificationCenterScheduler(),
        statusStore: NotificationScheduleStatusStore = NotificationScheduleStatusStore(),
        reminderLoader: @escaping @Sendable () -> [ReminderItem] = { [] },
        preferencesLoader: @escaping @Sendable () -> ReportReminderPreferences = {
            UserDefaultsReportReminderPreferencesStore().load()
        },
        reminderDetailsLoader: @escaping @Sendable () -> Bool = {
            UserDefaults.standard.bool(forKey: "notificationShowReminderDetails")
        },
        paydayLoader: @escaping @Sendable () -> Int = {
            max(UserDefaults.standard.integer(forKey: "payday"), 1)
        },
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.center = center
        self.statusStore = statusStore
        self.reminderLoader = reminderLoader
        self.preferencesLoader = preferencesLoader
        self.reminderDetailsLoader = reminderDetailsLoader
        self.paydayLoader = paydayLoader
        self.now = now
        self.calendar = calendar
    }

    @discardableResult
    func rebuild(reminders providedReminders: [ReminderItem]? = nil) async throws -> NotificationScheduleStatus {
        let referenceDate = now()
        let pending = await center.pendingRequests()
        let managedRequests = pending.filter {
            NotificationSchedulePlanner.isManaged(identifier: $0.identifier)
        }
        let managedIdentifiers = managedRequests.map(\.identifier)
        let unmanagedCount = pending.count - managedIdentifiers.count
        let capacity = max(
            NotificationSchedulePlanner.maximumPendingRequests - unmanagedCount,
            0
        )
        let candidates = NotificationSchedulePlanner.candidates(
            reminders: providedReminders ?? reminderLoader(),
            reportPreferences: preferencesLoader(),
            referenceDate: referenceDate,
            calendar: calendar,
            payday: paydayLoader(),
            includeReminderDetails: reminderDetailsLoader()
        )
        let selection = NotificationScheduleSelection.make(
            candidates: candidates,
            capacity: capacity
        )

        let allowsTimeSensitiveNotifications = await center.supportsTimeSensitiveNotifications()
        await center.removePendingRequests(withIdentifiers: managedIdentifiers)
        do {
            for candidate in selection.selected {
                try await center.add(request(
                    for: candidate,
                    allowsTimeSensitiveNotifications: allowsTimeSensitiveNotifications
                ))
            }
        } catch {
            let current = await center.pendingRequests()
            let identifiers = current
                .map(\.identifier)
                .filter(NotificationSchedulePlanner.isManaged(identifier:))
            await center.removePendingRequests(withIdentifiers: identifiers)
            // A failed replacement must not turn a previously working reminder
            // schedule into no schedule at all. Re-add the exact snapshot after
            // clearing only partially-added managed requests.
            for request in managedRequests {
                try? await center.add(request)
            }
            let status = status(
                selection: selection,
                unmanagedCount: unmanagedCount,
                errorMessage: error.localizedDescription,
                updatedAt: referenceDate,
                scheduledCountOnFailure: managedRequests.count
            )
            statusStore.save(status)
            throw error
        }

        let status = status(
            selection: selection,
            unmanagedCount: unmanagedCount,
            errorMessage: nil,
            updatedAt: referenceDate
        )
        statusStore.save(status)
        return status
    }

    private func request(
        for candidate: NotificationScheduleCandidate,
        allowsTimeSensitiveNotifications: Bool
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = candidate.title
        content.body = candidate.body
        content.sound = .default
        content.interruptionLevel = candidate.interruption == .timeSensitive && allowsTimeSensitiveNotifications
            ? .timeSensitive
            : .active
        if case .report(let period) = candidate.kind {
            content.userInfo = [ReportRoute.notificationPeriodUserInfoKey: period.rawValue]
        }
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: candidate.dateComponents,
            repeats: candidate.repeats
        )
        return UNNotificationRequest(
            identifier: candidate.identifier,
            content: content,
            trigger: trigger
        )
    }

    private func status(
        selection: NotificationScheduleSelection,
        unmanagedCount: Int,
        errorMessage: String?,
        updatedAt: Date,
        scheduledCountOnFailure: Int? = nil
    ) -> NotificationScheduleStatus {
        let reminderIDs = Set(selection.dropped.compactMap { candidate -> UUID? in
            if case .reminder(let id, _) = candidate.kind { return id }
            return nil
        })
        let periods = Set(selection.dropped.compactMap { candidate -> ReportPeriod? in
            if case .report(let period) = candidate.kind { return period }
            return nil
        })
        return NotificationScheduleStatus(
            scheduledCount: errorMessage == nil ? selection.selected.count : (scheduledCountOnFailure ?? 0),
            capacity: selection.capacity,
            unmanagedCount: unmanagedCount,
            droppedReminderIDs: reminderIDs.sorted { $0.uuidString < $1.uuidString },
            droppedReportPeriods: periods.sorted { $0.rawValue < $1.rawValue },
            errorMessage: errorMessage,
            updatedAt: updatedAt
        )
    }
}
