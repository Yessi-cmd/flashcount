import Foundation

enum ReminderStore {
    private static var fileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("flashcount-reminders.json")
    }

    static func load() -> [ReminderItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([ReminderItem].self, from: data)
        } catch {
            // 文件损坏时，备份损坏文件而不是静默覆盖
            let backupURL = fileURL.deletingPathExtension()
                .appendingPathExtension("corrupted-\(ISO8601DateFormatter().string(from: Date())).json")
            try? FileManager.default.moveItem(at: fileURL, to: backupURL)
            print("提醒文件损坏，已备份到: \(backupURL.lastPathComponent), 错误: \(error.localizedDescription)")
            return []
        }
    }

    static func save(_ reminders: [ReminderItem]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(reminders)
        try data.write(to: fileURL, options: .atomic)
    }

    static func replace(with reminders: [ReminderItem]) throws {
        try save(reminders)
    }
}
