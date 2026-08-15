import Foundation

/// 单个记账模板的使用记录。模板模型保持 SwiftData 结构不变，
/// 使用频率只作为轻量偏好存在 UserDefaults，避免为了排序引入新迁移。
struct TemplateUsageRecord: Codable, Equatable {
    var useCount: Int
    var lastUsedAt: Date

    static let initial = TemplateUsageRecord(useCount: 0, lastUsedAt: .distantPast)
}

/// 模板使用记录的 UserDefaults 读写。
struct TemplateUsageStore {
    static let storageKey = "templateUsage.v1"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func record(_ templateID: UUID, at date: Date = Date()) {
        var records = load()
        var record = records[templateID] ?? .initial
        record.useCount += 1
        record.lastUsedAt = date
        records[templateID] = record
        save(records)
    }

    func load() -> [UUID: TemplateUsageRecord] {
        guard let data = userDefaults.data(forKey: Self.storageKey),
              let raw = try? JSONDecoder().decode([String: TemplateUsageRecord].self, from: data) else {
            return [:]
        }
        var records: [UUID: TemplateUsageRecord] = [:]
        for (key, value) in raw {
            guard let id = UUID(uuidString: key) else { continue }
            records[id] = value
        }
        return records
    }

    private func save(_ records: [UUID: TemplateUsageRecord]) {
        var raw: [String: TemplateUsageRecord] = [:]
        for (id, record) in records {
            raw[id.uuidString] = record
        }
        guard let data = try? JSONEncoder().encode(raw) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }
}

/// 模板横条的显示顺序：前 `pinnedCount` 个尊重手动排序，其余按
/// 最近使用时间、使用次数、原 sortOrder 自动提前。
enum TemplateDisplayOrder {
    static let pinnedTemplateCount = 2

    static func ordered(
        _ templates: [TransactionTemplate],
        usage: [UUID: TemplateUsageRecord],
        pinnedCount: Int = pinnedTemplateCount
    ) -> [TransactionTemplate] {
        guard !templates.isEmpty else { return [] }
        let safePinnedCount = min(max(pinnedCount, 0), templates.count)
        let pinned = Array(templates.prefix(safePinnedCount))
        let flexible = templates.dropFirst(safePinnedCount).sorted { lhs, rhs in
            let lhsUsage = usage[lhs.id]
            let rhsUsage = usage[rhs.id]

            if let lhsUsage, let rhsUsage {
                if lhsUsage.lastUsedAt != rhsUsage.lastUsedAt {
                    return lhsUsage.lastUsedAt > rhsUsage.lastUsedAt
                }
                if lhsUsage.useCount != rhsUsage.useCount {
                    return lhsUsage.useCount > rhsUsage.useCount
                }
            } else if lhsUsage != nil {
                return true
            } else if rhsUsage != nil {
                return false
            }

            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return pinned + flexible
    }
}
