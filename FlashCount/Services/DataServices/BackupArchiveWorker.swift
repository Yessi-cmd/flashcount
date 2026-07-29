import Foundation

/// Encodes and writes value-only backup snapshots away from the main actor.
///
/// SwiftData models are converted to DTOs before crossing this actor boundary;
/// the worker never touches a `ModelContext` or a persisted model.
actor BackupArchiveWorker {
    static let shared = BackupArchiveWorker()

    func encode(_ backup: DataBackupService.BackupData) throws -> Data {
        try Self.encodeSynchronously(backup)
    }

    func write(
        _ backup: DataBackupService.BackupData,
        timestamp: Date
    ) throws -> URL {
        let data = try Self.encodeSynchronously(backup)
        return try Self.writeSynchronously(data, timestamp: timestamp)
    }

    nonisolated static func encodeSynchronously(
        _ backup: DataBackupService.BackupData
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    nonisolated static func writeSynchronously(
        _ data: Data,
        timestamp: Date
    ) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "FlashCount_Backup_\(formatter.string(from: timestamp)).json"
        let url = FileManager.default.temporaryDirectory.appending(path: filename)
        try data.write(to: url, options: .atomic)
        return url
    }
}
