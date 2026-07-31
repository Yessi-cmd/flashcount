import Foundation
import SwiftData

/// 订阅续费提醒在通知调度里需要的全部信息。刻意最简：只带名称、日期与提前天数，
/// **绝不含金额**——锁屏通知绕过 App 内隐私锁，金额会泄露敏感信息。
struct SubscriptionRenewalItem: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let nextRenewalDate: Date
    let remindBeforeDays: Int?
}

/// `Subscription` 模型的派生态：把未归档订阅镜像进 UserDefaults，
/// 供 `NotificationScheduleCoordinator` 的 `subscriptionLoader` 读取。
///
/// 这是**纯派生的调度镜像，不是权威存储**——真源是 SwiftData 里的 `Subscription`。
/// 因此任何变更订阅的地方都必须在同一事务边界调用 `refresh(from:)`
/// （`SubscriptionService` 的所有写路径、备份导入、App 启动兜底都这么做），
/// 否则通知排期会用到过期数据。
struct SubscriptionRenewalSnapshotStore {
    static let key = "subscriptionRenewalSnapshot.v1"

    let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> [SubscriptionRenewalItem] {
        guard let data = userDefaults.data(forKey: Self.key),
              let items = try? decoder.decode([SubscriptionRenewalItem].self, from: data) else {
            return []
        }
        return items
    }

    func save(_ items: [SubscriptionRenewalItem]) {
        guard let data = try? encoder.encode(items) else { return }
        userDefaults.set(data, forKey: Self.key)
    }

    /// 从模型重建快照：只取未归档订阅，映射成值类型后保存。
    @discardableResult
    static func refresh(
        from subscriptions: [Subscription],
        userDefaults: UserDefaults = .standard
    ) -> [SubscriptionRenewalItem] {
        let items = subscriptions
            .filter { !$0.isArchived }
            .map {
                SubscriptionRenewalItem(
                    id: $0.id,
                    name: $0.name,
                    nextRenewalDate: $0.nextRenewalDate,
                    remindBeforeDays: $0.remindBeforeDays
                )
            }
        SubscriptionRenewalSnapshotStore(userDefaults: userDefaults).save(items)
        return items
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
