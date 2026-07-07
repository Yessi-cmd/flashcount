import Foundation

struct ReminderItem: Identifiable, Codable, Equatable {
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

enum ReminderIntensity: String, CaseIterable, Codable, Identifiable {
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
