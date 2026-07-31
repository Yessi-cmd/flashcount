import Foundation

/// 订阅续费通知点按的路由。镜像 `QuickEntryRoute` / `ReportRoute` 的
/// UserDefaults 存/取模式：通知点按与 UI 不在同一次进程活动里，请求先落在
/// UserDefaults，由 `MainTabView` 取用。`consume()` 取走即清零——重复消费
/// 会让订阅页在用户关掉后又自己弹回来。
enum SubscriptionRoute {
    static let notificationSubscriptionIDUserInfoKey = "flashcount.subscription.id"
    static let requestKey = "shouldShowSubscription"
    static let payloadKey = "subscriptionRoutePayload.v1"

    /// 从通知 userInfo 里读出订阅 id，存入 payload 并置标志。返回是否成功路由。
    @discardableResult
    static func requestFromNotification(
        userInfo: [AnyHashable: Any],
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard let rawID = userInfo[notificationSubscriptionIDUserInfoKey] as? String,
              let id = UUID(uuidString: rawID) else { return false }
        userDefaults.set(id.uuidString, forKey: payloadKey)
        userDefaults.set(true, forKey: requestKey)
        return true
    }

    /// 取走请求并返回要展示的订阅 id；取走即清零。
    static func consume(userDefaults: UserDefaults = .standard) -> UUID? {
        guard userDefaults.bool(forKey: requestKey) else { return nil }
        userDefaults.set(false, forKey: requestKey)
        guard let rawID = userDefaults.string(forKey: payloadKey),
              let id = UUID(uuidString: rawID) else {
            userDefaults.removeObject(forKey: payloadKey)
            return nil
        }
        userDefaults.removeObject(forKey: payloadKey)
        return id
    }
}
