import Foundation
import UserNotifications

enum ReminderNotificationService {
    private static let delegate = ReminderNotificationDelegate()

    static func configure() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func schedule(_ reminder: ReminderItem) async throws {
        cancel(reminderID: reminder.id)

        let center = UNUserNotificationCenter.current()
        for (index, offset) in reminder.intensity.notificationOffsets.enumerated() {
            let fireDate = reminder.dueDate.addingTimeInterval(offset)
            guard fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.note.isEmpty ? body(for: reminder, index: index) : reminder.note
            content.sound = .default
            content.interruptionLevel = reminder.intensity == .strong ? .timeSensitive : .active

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: identifier(for: reminder.id, index: index), content: content, trigger: trigger)
            try await center.add(request)
        }
    }

    static func cancel(reminderID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers(for: reminderID))
    }

    private static func body(for reminder: ReminderItem, index: Int) -> String {
        if reminder.intensity == .strong && index > 0 {
            return "还没有标记完成，记得处理这件事。"
        }
        return "到时间了，打开 FlashCount 标记完成。"
    }

    private static func identifier(for reminderID: UUID, index: Int) -> String {
        "flashcount.reminder.\(reminderID.uuidString).\(index)"
    }

    private static func identifiers(for reminderID: UUID) -> [String] {
        let maxOffsetCount = ReminderIntensity.allCases.map(\.notificationOffsets.count).max() ?? 0
        return (0..<maxOffsetCount).map { identifier(for: reminderID, index: $0) }
    }
}

private final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
