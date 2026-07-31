import Foundation
import UserNotifications

/// 提醒通知调度的抽象，便于测试替换真实通知中心。
protocol ReminderNotificationScheduling {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async -> Bool
    func rebuild(reminders: [ReminderItem]) async throws
}

/// 提醒的通知权限申请与分类注册。
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

    static func rebuild(reminders: [ReminderItem]) async throws {
        try await NotificationScheduleCoordinator.shared.rebuild(reminders: reminders)
    }
}

/// 走真实通知中心的提醒调度实现。
struct SystemReminderNotificationScheduler: ReminderNotificationScheduling {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await ReminderNotificationService.authorizationStatus()
    }

    func requestAuthorization() async -> Bool {
        await ReminderNotificationService.requestAuthorization()
    }

    func rebuild(reminders: [ReminderItem]) async throws {
        try await ReminderNotificationService.rebuild(reminders: reminders)
    }
}

private final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if ReportRoute.requestFromNotification(
            userInfo: notification.request.content.userInfo,
            deliveredAt: notification.date,
            presentation: .foregroundSheet
        ) {
            // App 内会直接展示完整报表；保留声音与通知中心记录，避免再叠加系统横幅。
            return [.list, .sound]
        }
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        ReportRoute.requestFromNotification(
            userInfo: response.notification.request.content.userInfo,
            deliveredAt: response.notification.date
        )
        SubscriptionRoute.requestFromNotification(
            userInfo: response.notification.request.content.userInfo
        )
    }
}
