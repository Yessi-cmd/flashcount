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
        return (try? decoder.decode([ReminderItem].self, from: data)) ?? []
    }

    static func save(_ reminders: [ReminderItem]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(reminders)
        try data.write(to: fileURL, options: .atomic)
    }
}
