import Foundation
import SwiftData

/// 数据备份/恢复服务 — 全量备份所有数据。
/// 按职责拆分为四个文件：
/// - `BackupDTOs.swift`：`CodableMoney` 与全部 DTO / 结果类型
/// - `BackupExporter.swift`：导出 JSON / 文件
/// - `BackupImporter.swift`：导入、预览与中断恢复日志
/// - `BackupValidator.swift`：版本与内容校验
@MainActor
final class DataBackupService {

    nonisolated static let currentBackupVersion = "1.10.0"
    nonisolated static let minimumSupportedBackupVersion = "1.0.0"

    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
}
