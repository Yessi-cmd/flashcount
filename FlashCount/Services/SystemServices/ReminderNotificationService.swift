import Foundation
import UserNotifications

protocol ReminderNotificationScheduling {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async -> Bool
    func schedule(_ reminder: ReminderItem) async throws
    func cancel(reminderID: UUID)
}

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
        _ = reminder
        try await NotificationScheduleCoordinator.shared.rebuild()
    }

    static func cancel(reminderID: UUID) {
        _ = reminderID
        Task { _ = try? await NotificationScheduleCoordinator.shared.rebuild() }
    }
}

struct SystemReminderNotificationScheduler: ReminderNotificationScheduling {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await ReminderNotificationService.authorizationStatus()
    }

    func requestAuthorization() async -> Bool {
        await ReminderNotificationService.requestAuthorization()
    }

    func schedule(_ reminder: ReminderItem) async throws {
        try await ReminderNotificationService.schedule(reminder)
    }

    func cancel(reminderID: UUID) {
        ReminderNotificationService.cancel(reminderID: reminderID)
    }
}

private final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        ReportRoute.requestFromNotification(
            userInfo: response.notification.request.content.userInfo,
            deliveredAt: response.notification.date
        )
    }
}
