import Foundation

/// 提醒的值类型。
///
/// 提醒最初存在独立 JSON 文件里，现已迁入 SwiftData（`Reminder` 模型）。
/// 这个 `Codable` 值类型保留下来是因为备份格式与一次性的旧文件导入仍用它，
/// 同时它 `Sendable`，可以安全地交给通知调度的 actor。
struct ReminderItem: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var note: String
    var dueDate: Date
    var intensity: ReminderIntensity
    var isCompleted: Bool
    var createdAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        note: String = "",
        dueDate: Date,
        intensity: ReminderIntensity = .normal,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.dueDate = dueDate
        self.intensity = intensity
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    var isOverdue: Bool {
        !isCompleted && dueDate < Date()
    }
}

/// 提醒强度。强提醒会安排多次本地通知，普通提醒只有一次。
/// `rawValue` 进备份，改动会破坏旧备份。
enum ReminderIntensity: String, CaseIterable, Codable, Identifiable, Sendable {
    case normal = "普通提醒"
    case strong = "强提醒"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .normal: return "bell.fill"
        case .strong: return "bell.and.waves.left.and.right.fill"
        }
    }

    var description: String {
        switch self {
        case .normal: return "到点响一次"
        case .strong: return "到点后追加多次提醒"
        }
    }

    var notificationOffsets: [TimeInterval] {
        switch self {
        case .normal:
            return [0]
        case .strong:
            return [0, 60, 180, 300, 600]
        }
    }
}
