import Foundation
import SwiftData

/// Persistent reminder record. `ReminderItem` remains the Codable transfer
/// type used by backups and the one-time legacy JSON migration.
@Model
final class Reminder {
    var id: UUID
    var title: String
    var note: String
    var dueDate: Date
    var intensityRawValue: String
    var isCompleted: Bool
    var createdAt: Date
    var completedAt: Date?

    init(item: ReminderItem) {
        id = item.id
        title = item.title
        note = item.note
        dueDate = item.dueDate
        intensityRawValue = item.intensity.rawValue
        isCompleted = item.isCompleted
        createdAt = item.createdAt
        completedAt = item.completedAt
    }

    var item: ReminderItem {
        ReminderItem(
            id: id,
            title: title,
            note: note,
            dueDate: dueDate,
            intensity: ReminderIntensity(rawValue: intensityRawValue) ?? .normal,
            isCompleted: isCompleted,
            createdAt: createdAt,
            completedAt: completedAt
        )
    }
}
