import Foundation

protocol ReminderPersisting {
    func load() -> [ReminderItem]
    func save(_ reminders: [ReminderItem]) throws
}

struct FileReminderStore: ReminderPersisting {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.fileURL = documents.appendingPathComponent("flashcount-reminders.json")
        }
    }

    func load() -> [ReminderItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([ReminderItem].self, from: data)
        } catch {
            let backupURL = fileURL.deletingPathExtension()
                .appendingPathExtension("corrupted-\(ISO8601DateFormatter().string(from: Date())).json")
            try? FileManager.default.moveItem(at: fileURL, to: backupURL)
            print("提醒文件损坏，已备份到: \(backupURL.lastPathComponent), 错误: \(error.localizedDescription)")
            return []
        }
    }

    func save(_ reminders: [ReminderItem]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(reminders)
        try data.write(to: fileURL, options: .atomic)
    }
}

struct ReminderMutationService {
    let store: any ReminderPersisting

    func adding(_ reminder: ReminderItem, to reminders: [ReminderItem]) throws -> [ReminderItem] {
        var updated = reminders
        updated.append(reminder)
        try store.save(updated)
        return updated
    }

    func completing(id: UUID, in reminders: [ReminderItem], at date: Date = Date()) throws -> [ReminderItem] {
        var updated = reminders
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return reminders }
        updated[index].isCompleted = true
        updated[index].completedAt = date
        try store.save(updated)
        return updated
    }

    func deleting(id: UUID, from reminders: [ReminderItem]) throws -> [ReminderItem] {
        let updated = reminders.filter { $0.id != id }
        try store.save(updated)
        return updated
    }
}

enum ReminderStore {
    private static let store = FileReminderStore()

    static func load() -> [ReminderItem] {
        store.load()
    }

    static func save(_ reminders: [ReminderItem]) throws {
        try store.save(reminders)
    }

    static func replace(with reminders: [ReminderItem]) throws {
        try save(reminders)
    }
}
