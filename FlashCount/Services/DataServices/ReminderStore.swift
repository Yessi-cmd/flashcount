import Foundation
import SwiftData

/// Legacy JSON codec. New reminder writes never go through this file; it
/// remains untouched after a successful import so an existing installation
/// always retains its original local data.
struct FileReminderStore {
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

private enum ReminderStorageMigration {
    static let legacyMigrationKey = "reminder-storage-swiftdata-migration-v1"
}

@MainActor
final class ReminderDataService {

    private let modelContext: ModelContext
    private let legacyStore: FileReminderStore
    private let userDefaults: UserDefaults
    private let migrationKey: String

    init(
        modelContext: ModelContext,
        legacyStore: FileReminderStore = FileReminderStore(),
        userDefaults: UserDefaults = .standard,
        migrationKey: String = ReminderStorageMigration.legacyMigrationKey
    ) {
        self.modelContext = modelContext
        self.legacyStore = legacyStore
        self.userDefaults = userDefaults
        self.migrationKey = migrationKey
    }

    func load() throws -> [ReminderItem] {
        try modelContext.fetch(FetchDescriptor<Reminder>()).map(\.item)
    }

    @discardableResult
    func migrateLegacyFileIfNeeded() throws -> Int {
        guard !userDefaults.bool(forKey: migrationKey) else { return 0 }

        let existingIDs = Set(try load().map(\.id))
        var importedIDs = Set<UUID>()
        let legacyReminders = legacyStore.load()
        let newReminders = legacyReminders.filter {
            !existingIDs.contains($0.id) && importedIDs.insert($0.id).inserted
        }

        if !newReminders.isEmpty {
            for reminder in newReminders {
                modelContext.insert(Reminder(item: reminder))
            }
            try saveChanges()
        }

        // Mark only after the database commit. The legacy file is deliberately
        // retained rather than deleted or overwritten.
        userDefaults.set(true, forKey: migrationKey)
        return newReminders.count
    }

    /// A replace restore is authoritative for reminders, so the retained legacy
    /// JSON must not be imported afterward as stale data.
    func markLegacyFileMigrationComplete() {
        userDefaults.set(true, forKey: migrationKey)
    }

    func add(_ reminder: ReminderItem) throws -> [ReminderItem] {
        let existingIDs = Set(try load().map(\.id))
        guard !existingIDs.contains(reminder.id) else { return try load() }

        modelContext.insert(Reminder(item: reminder))
        try saveChanges()
        return try load()
    }

    func complete(id: UUID, at date: Date = Date()) throws -> [ReminderItem] {
        guard let reminder = try reminder(withID: id) else { return try load() }
        reminder.isCompleted = true
        reminder.completedAt = date
        try saveChanges()
        return try load()
    }

    func delete(id: UUID) throws -> [ReminderItem] {
        guard let reminder = try reminder(withID: id) else { return try load() }
        modelContext.delete(reminder)
        try saveChanges()
        return try load()
    }

    private func reminder(withID id: UUID) throws -> Reminder? {
        try modelContext.fetch(FetchDescriptor<Reminder>()).first { $0.id == id }
    }

    private func saveChanges() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
