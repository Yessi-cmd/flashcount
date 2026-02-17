import Foundation
import SwiftData

/// 数据备份/恢复服务 — 防止卸载 App 丢数据
@MainActor
final class DataBackupService {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - 导出

    struct BackupData: Codable {
        let version: String
        let createdAt: Date
        let physicalAssets: [PhysicalAssetDTO]
    }

    struct PhysicalAssetDTO: Codable {
        let id: String
        let name: String
        let category: String
        let purchasePrice: Double
        let purchaseDate: Date
        let salvageValue: Double
        let targetDailyCost: Double
        let soldPrice: Double?
        let soldDate: Date?
        let note: String
        let isArchived: Bool
    }

    /// 导出所有数据为 JSON Data
    func exportJSON() throws -> Data {
        let assets = (try? modelContext.fetch(FetchDescriptor<PhysicalAsset>())) ?? []

        let assetDTOs = assets.map { a in
            PhysicalAssetDTO(
                id: a.id.uuidString,
                name: a.name,
                category: a.category.rawValue,
                purchasePrice: NSDecimalNumber(decimal: a.purchasePrice).doubleValue,
                purchaseDate: a.purchaseDate,
                salvageValue: NSDecimalNumber(decimal: a.salvageValue).doubleValue,
                targetDailyCost: NSDecimalNumber(decimal: a.targetDailyCost).doubleValue,
                soldPrice: a.soldPrice.map { NSDecimalNumber(decimal: $0).doubleValue },
                soldDate: a.soldDate,
                note: a.note,
                isArchived: a.isArchived
            )
        }

        let backup = BackupData(
            version: "1.2.0",
            createdAt: Date(),
            physicalAssets: assetDTOs
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    /// 导出到临时文件并返回 URL（用于 ShareSheet）
    func exportToFile() throws -> URL {
        let data = try exportJSON()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "FlashCount_Backup_\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }

    // MARK: - 导入

    struct ImportResult {
        let assetsImported: Int
        let assetsSkipped: Int  // 已存在的
        var summary: String {
            "导入完成：新增 \(assetsImported) 项，跳过 \(assetsSkipped) 项已存在的数据"
        }
    }

    /// 从 JSON 文件导入数据
    func importJSON(from url: URL) throws -> ImportResult {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(BackupData.self, from: data)

        // 获取已有资产的 ID
        let existingAssets = (try? modelContext.fetch(FetchDescriptor<PhysicalAsset>())) ?? []
        let existingIDs = Set(existingAssets.map { $0.id.uuidString })

        var imported = 0
        var skipped = 0

        for dto in backup.physicalAssets {
            if existingIDs.contains(dto.id) {
                skipped += 1
                continue
            }

            guard let category = PhysicalAssetCategory(rawValue: dto.category) else {
                skipped += 1
                continue
            }

            let asset = PhysicalAsset(
                name: dto.name,
                category: category,
                purchasePrice: Decimal(dto.purchasePrice),
                purchaseDate: dto.purchaseDate,
                salvageValue: Decimal(dto.salvageValue),
                targetDailyCost: Decimal(dto.targetDailyCost),
                note: dto.note
            )
            if let id = UUID(uuidString: dto.id) {
                asset.id = id
            }
            asset.isArchived = dto.isArchived
            asset.soldPrice = dto.soldPrice.map { Decimal($0) }
            asset.soldDate = dto.soldDate

            modelContext.insert(asset)
            imported += 1
        }

        try modelContext.save()
        return ImportResult(assetsImported: imported, assetsSkipped: skipped)
    }
}
