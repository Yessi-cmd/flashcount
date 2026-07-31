import Foundation
import UserNotifications

/// 一条待安排通知的来源：某个提醒的第几次触发、某种周期的报表提醒，或一笔订阅的续费提醒。
enum NotificationCandidateKind: Equatable {
    case reminder(id: UUID, offsetIndex: Int)
    case report(period: ReportPeriod)
    case subscriptionRenewal(id: UUID)
}

/// 通知的打扰级别。强提醒用 `.timeSensitive` 以穿透专注模式。
enum NotificationInterruptionKind: Equatable {
    case active
    case timeSensitive
}

/// 一条候选通知。`sortPriority` 保证名额不足时先保住提醒的首次触发，
/// 再考虑后续触发和报表提醒。
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
        case .subscriptionRenewal: return 1
        case .report: return 2
        }
    }
}

/// 在系统名额上限内的取舍结果：`selected` 已安排，`dropped` 被放弃。
///
/// 排序按触发时间优先、再按 `sortPriority`、最后按标识符——最后一项是为了
/// 让结果稳定可测，避免同时刻候选的取舍随机。
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

/// 把提醒与报表偏好推演成候选通知，并在系统名额内做取舍。
///
/// iOS 每个 App 最多 64 条待处理本地通知，超出的会被系统静默丢弃。
/// 因此这里必须显式取舍并把被放弃的部分记录下来告知用户，
/// 否则「设置了提醒但没响」将无从解释。
enum NotificationSchedulePlanner {
    static let maximumPendingRequests = 64
    static let reminderIdentifierPrefix = "flashcount.reminder."
    static let reportIdentifierPrefix = ReportReminderSchedulePlanner.identifierPrefix
    static let subscriptionIdentifierPrefix = "flashcount.subscription."

    static func candidates(
        reminders: [ReminderItem],
        reportPreferences: ReportReminderPreferences,
        subscriptionRenewals: [SubscriptionRenewalItem] = [],
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
            + subscriptionRenewalCandidates(
                items: subscriptionRenewals,
                referenceDate: referenceDate,
                calendar: calendar
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
            || identifier.hasPrefix(subscriptionIdentifierPrefix)
    }

    /// 每笔订阅在「续费日前 N 天」触发一次提醒。已过触发时间或未设提前天数的
    /// 订阅不安排。文案只带订阅名称，绝不含金额——锁屏通知会绕过 App 内隐私锁。
    private static func subscriptionRenewalCandidates(
        items: [SubscriptionRenewalItem],
        referenceDate: Date,
        calendar: Calendar
    ) -> [NotificationScheduleCandidate] {
        items.compactMap { item -> NotificationScheduleCandidate? in
            guard let remindBeforeDays = item.remindBeforeDays, remindBeforeDays > 0,
                  let fireDate = calendar.date(
                    byAdding: .day,
                    value: -remindBeforeDays,
                    to: item.nextRenewalDate
                  ),
                  fireDate > referenceDate else { return nil }
            return NotificationScheduleCandidate(
                identifier: "\(subscriptionIdentifierPrefix)\(item.id.uuidString)",
                kind: .subscriptionRenewal(id: item.id),
                nextTriggerDate: fireDate,
                dateComponents: calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: fireDate
                ),
                repeats: false,
                title: "订阅续费提醒",
                body: "「\(item.name)」将在 \(item.nextRenewalDate.formatted(date: .abbreviated, time: .omitted)) 续费。",
                interruption: .active
            )
        }
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

/// 上一次通知安排的结果，持久化后供设置页说明情况。
///
/// `summary` 是给用户看的一句话：安排失败或有远期通知被放弃时必须说清，
/// 静默失败会让用户以为提醒已经生效。
struct NotificationScheduleStatus: Codable, Equatable {
    let scheduledCount: Int
    let capacity: Int
    let unmanagedCount: Int
    let droppedReminderIDs: [UUID]
    let droppedReportPeriods: [ReportPeriod]
    let droppedSubscriptionIDs: [UUID]
    let errorMessage: String?
    let updatedAt: Date

    init(
        scheduledCount: Int,
        capacity: Int,
        unmanagedCount: Int,
        droppedReminderIDs: [UUID],
        droppedReportPeriods: [ReportPeriod],
        droppedSubscriptionIDs: [UUID] = [],
        errorMessage: String?,
        updatedAt: Date
    ) {
        self.scheduledCount = scheduledCount
        self.capacity = capacity
        self.unmanagedCount = unmanagedCount
        self.droppedReminderIDs = droppedReminderIDs
        self.droppedReportPeriods = droppedReportPeriods
        self.droppedSubscriptionIDs = droppedSubscriptionIDs
        self.errorMessage = errorMessage
        self.updatedAt = updatedAt
    }

    /// 自定义解码：老版本存下的 status blob 没有 `droppedSubscriptionIDs` 等字段，
    /// 用 `decodeIfPresent` 补默认值，保证旧数据仍能读出来。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scheduledCount = try container.decode(Int.self, forKey: .scheduledCount)
        capacity = try container.decode(Int.self, forKey: .capacity)
        unmanagedCount = try container.decode(Int.self, forKey: .unmanagedCount)
        droppedReminderIDs = try container.decodeIfPresent([UUID].self, forKey: .droppedReminderIDs) ?? []
        droppedReportPeriods = try container.decodeIfPresent([ReportPeriod].self, forKey: .droppedReportPeriods) ?? []
        droppedSubscriptionIDs = try container.decodeIfPresent([UUID].self, forKey: .droppedSubscriptionIDs) ?? []
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

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
        !droppedReminderIDs.isEmpty || !droppedReportPeriods.isEmpty || !droppedSubscriptionIDs.isEmpty
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

/// `NotificationScheduleStatus` 的 `UserDefaults` 读写。
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

    func saveFailure(_ error: Error, updatedAt: Date = .now) {
        save(NotificationScheduleStatus(
            scheduledCount: 0,
            capacity: NotificationSchedulePlanner.maximumPendingRequests,
            unmanagedCount: 0,
            droppedReminderIDs: [],
            droppedReportPeriods: [],
            errorMessage: error.localizedDescription,
            updatedAt: updatedAt
        ))
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

/// 对 `UNUserNotificationCenter` 的最小抽象，让排期逻辑可以在测试里
/// 用假实现验证——真实通知中心在单元测试环境下不可用。
protocol NotificationCenterScheduling: Sendable {
    func pendingRequests() async -> [UNNotificationRequest]
    func supportsTimeSensitiveNotifications() async -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingRequests(withIdentifiers identifiers: [String]) async
}

/// 走真实 `UNUserNotificationCenter` 的实现。
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

/// 本地通知安排的唯一出口。
///
/// 做成 actor 是因为重排会被启动、设置变更、导入完成等多处并发触发，
/// 而「先清空再写入」这个过程若交错执行会留下重复或缺失的通知。
/// 各数据来源以闭包注入，便于测试替换。
actor NotificationScheduleCoordinator {
    static let shared = NotificationScheduleCoordinator()

    private let center: any NotificationCenterScheduling
    private let statusStore: NotificationScheduleStatusStore
    private let reminderLoader: @Sendable () -> [ReminderItem]
    private let preferencesLoader: @Sendable () -> ReportReminderPreferences
    private let subscriptionLoader: @Sendable () -> [SubscriptionRenewalItem]
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
        subscriptionLoader: @escaping @Sendable () -> [SubscriptionRenewalItem] = {
            SubscriptionRenewalSnapshotStore().load()
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
        self.subscriptionLoader = subscriptionLoader
        self.reminderDetailsLoader = reminderDetailsLoader
        self.paydayLoader = paydayLoader
        self.now = now
        self.calendar = calendar
    }

    @discardableResult
    func rebuild(
        reminders providedReminders: [ReminderItem]? = nil,
        reportPreferences providedReportPreferences: ReportReminderPreferences? = nil,
        subscriptions providedSubscriptions: [SubscriptionRenewalItem]? = nil
    ) async throws -> NotificationScheduleStatus {
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
            reportPreferences: providedReportPreferences ?? preferencesLoader(),
            subscriptionRenewals: providedSubscriptions ?? subscriptionLoader(),
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
            // clearing only partially-added managed requests, while keeping an
            // accurate count if the restoration itself is partially rejected.
            var restoredCount = 0
            var restorationErrors: [String] = []
            for request in managedRequests {
                do {
                    try await center.add(request)
                    restoredCount += 1
                } catch {
                    restorationErrors.append(error.localizedDescription)
                }
            }
            let restorationMessage = restorationErrors.isEmpty
                ? error.localizedDescription
                : "\(error.localizedDescription)；旧通知仅恢复 \(restoredCount)/\(managedRequests.count) 条"
            let status = status(
                selection: selection,
                unmanagedCount: unmanagedCount,
                errorMessage: restorationMessage,
                updatedAt: referenceDate,
                scheduledCountOnFailure: restoredCount
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
        if case .subscriptionRenewal(let id) = candidate.kind {
            content.userInfo = [SubscriptionRoute.notificationSubscriptionIDUserInfoKey: id.uuidString]
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
        let subscriptionIDs = Set(selection.dropped.compactMap { candidate -> UUID? in
            if case .subscriptionRenewal(let id) = candidate.kind { return id }
            return nil
        })
        return NotificationScheduleStatus(
            scheduledCount: errorMessage == nil ? selection.selected.count : (scheduledCountOnFailure ?? 0),
            capacity: selection.capacity,
            unmanagedCount: unmanagedCount,
            droppedReminderIDs: reminderIDs.sorted { $0.uuidString < $1.uuidString },
            droppedReportPeriods: periods.sorted { $0.rawValue < $1.rawValue },
            droppedSubscriptionIDs: subscriptionIDs.sorted { $0.uuidString < $1.uuidString },
            errorMessage: errorMessage,
            updatedAt: updatedAt
        )
    }
}
