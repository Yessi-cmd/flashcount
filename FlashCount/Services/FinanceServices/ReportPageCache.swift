import Foundation

/// 已完成周期的报表在数据未变时结果是确定的，翻历史页不必重复取数与计算。
/// 只缓存非「当前进行中」的目标：`.current` 的参照时刻每秒都在变，
/// 缓存键永远打不中，只会白占内存。
actor ReportPageCache {
    static let shared = ReportPageCache()

    struct Key: Hashable, Sendable {
        let digest: Int
        let period: ReportPeriod
        let targetKind: String
        let targetReferenceDate: Date
        let payday: Int
        let weekendMultiplierPercent: Int
    }

    private static let capacity = 12

    private var entries: [Key: ReportPageCalculation] = [:]
    private var recency: [Key] = []

    func value(for key: Key) -> ReportPageCalculation? {
        guard let value = entries[key] else { return nil }
        touch(key)
        return value
    }

    func insert(_ value: ReportPageCalculation, for key: Key) {
        entries[key] = value
        touch(key)
        while recency.count > Self.capacity, let oldest = recency.first {
            recency.removeFirst()
            entries.removeValue(forKey: oldest)
        }
    }

    /// 数据变了就整体作废：键里带 digest，旧条目不会被误用，
    /// 但留着也没有价值，不如让内存尽快回收。
    func removeAll() {
        entries.removeAll()
        recency.removeAll()
    }

    private func touch(_ key: Key) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}
