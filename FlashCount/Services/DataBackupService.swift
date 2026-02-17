import Foundation
import SwiftData

/// 数据备份/恢复服务 — 全量备份所有数据
@MainActor
final class DataBackupService {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - DTO 定义

    struct BackupData: Codable {
        let version: String
        let createdAt: Date
        let categories: [CategoryDTO]
        let ledgers: [LedgerDTO]
        let transactions: [TransactionDTO]
        let assets: [AssetDTO]
        let physicalAssets: [PhysicalAssetDTO]
        let recurringRules: [RecurringRuleDTO]
        let budgets: [BudgetDTO]
    }

    struct CategoryDTO: Codable {
        let id: String
        let name: String
        let icon: String
        let colorHex: String
        let isExpense: Bool
        let sortOrder: Int
        let isArchived: Bool
    }

    struct LedgerDTO: Codable {
        let id: String
        let name: String
        let icon: String
        let colorHex: String
        let isDefault: Bool
        let isArchived: Bool
        let createdAt: Date
        let sortOrder: Int
    }

    struct TransactionDTO: Codable {
        let id: String
        let amount: Double
        let isExpense: Bool
        let note: String
        let date: Date
        let createdAt: Date
        let categoryId: String?
        let ledgerId: String?
    }

    struct AssetDTO: Codable {
        let id: String
        let name: String
        let type: String
        let balance: Double
        let icon: String
        let colorHex: String
        let note: String
        let isArchived: Bool
        let updatedAt: Date
        let createdAt: Date
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

    struct RecurringRuleDTO: Codable {
        let id: String
        let title: String
        let amount: Double
        let isExpense: Bool
        let frequency: String
        let nextDueDate: Date
        let isActive: Bool
        let note: String
        let createdAt: Date
        let categoryId: String?
        let ledgerId: String?
    }

    struct BudgetDTO: Codable {
        let id: String
        let monthlyLimit: Double
        let year: Int
        let month: Int
        let createdAt: Date
        let ledgerId: String?
        let categoryId: String?
    }

    // MARK: - 导出

    func exportJSON() throws -> Data {
        let categories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        let ledgers = (try? modelContext.fetch(FetchDescriptor<Ledger>())) ?? []
        let transactions = (try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? []
        let assets = (try? modelContext.fetch(FetchDescriptor<Asset>())) ?? []
        let physicalAssets = (try? modelContext.fetch(FetchDescriptor<PhysicalAsset>())) ?? []
        let recurringRules = (try? modelContext.fetch(FetchDescriptor<RecurringRule>())) ?? []
        let budgets = (try? modelContext.fetch(FetchDescriptor<Budget>())) ?? []

        let backup = BackupData(
            version: "1.2.0",
            createdAt: Date(),
            categories: categories.map { c in
                CategoryDTO(id: c.id.uuidString, name: c.name, icon: c.icon,
                           colorHex: c.colorHex, isExpense: c.isExpense,
                           sortOrder: c.sortOrder, isArchived: c.isArchived)
            },
            ledgers: ledgers.map { l in
                LedgerDTO(id: l.id.uuidString, name: l.name, icon: l.icon,
                         colorHex: l.colorHex, isDefault: l.isDefault,
                         isArchived: l.isArchived, createdAt: l.createdAt,
                         sortOrder: l.sortOrder)
            },
            transactions: transactions.map { t in
                TransactionDTO(id: t.id.uuidString, amount: NSDecimalNumber(decimal: t.amount).doubleValue,
                              isExpense: t.isExpense, note: t.note, date: t.date,
                              createdAt: t.createdAt,
                              categoryId: t.category?.id.uuidString,
                              ledgerId: t.ledger?.id.uuidString)
            },
            assets: assets.map { a in
                AssetDTO(id: a.id.uuidString, name: a.name, type: a.type.rawValue,
                        balance: NSDecimalNumber(decimal: a.balance).doubleValue,
                        icon: a.icon, colorHex: a.colorHex, note: a.note,
                        isArchived: a.isArchived, updatedAt: a.updatedAt,
                        createdAt: a.createdAt)
            },
            physicalAssets: physicalAssets.map { a in
                PhysicalAssetDTO(id: a.id.uuidString, name: a.name,
                                category: a.category.rawValue,
                                purchasePrice: NSDecimalNumber(decimal: a.purchasePrice).doubleValue,
                                purchaseDate: a.purchaseDate,
                                salvageValue: NSDecimalNumber(decimal: a.salvageValue).doubleValue,
                                targetDailyCost: NSDecimalNumber(decimal: a.targetDailyCost).doubleValue,
                                soldPrice: a.soldPrice.map { NSDecimalNumber(decimal: $0).doubleValue },
                                soldDate: a.soldDate, note: a.note,
                                isArchived: a.isArchived)
            },
            recurringRules: recurringRules.map { r in
                RecurringRuleDTO(id: r.id.uuidString, title: r.title,
                                amount: NSDecimalNumber(decimal: r.amount).doubleValue,
                                isExpense: r.isExpense, frequency: r.frequency.rawValue,
                                nextDueDate: r.nextDueDate, isActive: r.isActive,
                                note: r.note, createdAt: r.createdAt,
                                categoryId: r.category?.id.uuidString,
                                ledgerId: r.ledger?.id.uuidString)
            },
            budgets: budgets.map { b in
                BudgetDTO(id: b.id.uuidString,
                         monthlyLimit: NSDecimalNumber(decimal: b.monthlyLimit).doubleValue,
                         year: b.year, month: b.month, createdAt: b.createdAt,
                         ledgerId: b.ledger?.id.uuidString,
                         categoryId: b.categoryId?.uuidString)
            }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

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
        var categoriesImported = 0
        var ledgersImported = 0
        var transactionsImported = 0
        var assetsImported = 0
        var physicalAssetsImported = 0
        var recurringRulesImported = 0
        var budgetsImported = 0
        var skipped = 0

        var summary: String {
            var parts: [String] = []
            if categoriesImported > 0 { parts.append("分类 \(categoriesImported)") }
            if ledgersImported > 0 { parts.append("账本 \(ledgersImported)") }
            if transactionsImported > 0 { parts.append("账单 \(transactionsImported)") }
            if assetsImported > 0 { parts.append("账户 \(assetsImported)") }
            if physicalAssetsImported > 0 { parts.append("实物资产 \(physicalAssetsImported)") }
            if recurringRulesImported > 0 { parts.append("周期规则 \(recurringRulesImported)") }
            if budgetsImported > 0 { parts.append("预算 \(budgetsImported)") }

            let importedStr = parts.isEmpty ? "无新数据" : "导入：" + parts.joined(separator: "、")
            let skippedStr = skipped > 0 ? "\n跳过 \(skipped) 项已有数据" : ""
            return importedStr + skippedStr
        }
    }

    func importJSON(from url: URL) throws -> ImportResult {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(BackupData.self, from: data)

        var result = ImportResult()

        // 1. 先导入分类和账本（它们被其他模型引用）
        let existingCategories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        let existingCategoryIDs = Set(existingCategories.map { $0.id.uuidString })
        var categoryMap: [String: Category] = [:]
        // 建立已有映射
        for c in existingCategories { categoryMap[c.id.uuidString] = c }

        for dto in backup.categories {
            if existingCategoryIDs.contains(dto.id) {
                result.skipped += 1
                continue
            }
            let cat = Category(name: dto.name, icon: dto.icon, colorHex: dto.colorHex,
                              isExpense: dto.isExpense, sortOrder: dto.sortOrder)
            if let id = UUID(uuidString: dto.id) { cat.id = id }
            cat.isArchived = dto.isArchived
            modelContext.insert(cat)
            categoryMap[dto.id] = cat
            result.categoriesImported += 1
        }

        let existingLedgers = (try? modelContext.fetch(FetchDescriptor<Ledger>())) ?? []
        let existingLedgerIDs = Set(existingLedgers.map { $0.id.uuidString })
        var ledgerMap: [String: Ledger] = [:]
        for l in existingLedgers { ledgerMap[l.id.uuidString] = l }

        for dto in backup.ledgers {
            if existingLedgerIDs.contains(dto.id) {
                result.skipped += 1
                continue
            }
            let ledger = Ledger(name: dto.name, icon: dto.icon, colorHex: dto.colorHex,
                               isDefault: dto.isDefault, sortOrder: dto.sortOrder)
            if let id = UUID(uuidString: dto.id) { ledger.id = id }
            ledger.isArchived = dto.isArchived
            modelContext.insert(ledger)
            ledgerMap[dto.id] = ledger
            result.ledgersImported += 1
        }

        // 2. 导入交易记录
        let existingTransactions = (try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? []
        let existingTransIDs = Set(existingTransactions.map { $0.id.uuidString })

        for dto in backup.transactions {
            if existingTransIDs.contains(dto.id) {
                result.skipped += 1
                continue
            }
            let t = Transaction(amount: Decimal(dto.amount), isExpense: dto.isExpense,
                               note: dto.note, date: dto.date,
                               category: dto.categoryId.flatMap { categoryMap[$0] },
                               ledger: dto.ledgerId.flatMap { ledgerMap[$0] })
            if let id = UUID(uuidString: dto.id) { t.id = id }
            modelContext.insert(t)
            result.transactionsImported += 1
        }

        // 3. 导入资产账户
        let existingAssets = (try? modelContext.fetch(FetchDescriptor<Asset>())) ?? []
        let existingAssetIDs = Set(existingAssets.map { $0.id.uuidString })

        for dto in backup.assets {
            if existingAssetIDs.contains(dto.id) {
                result.skipped += 1
                continue
            }
            guard let assetType = AssetType(rawValue: dto.type) else {
                result.skipped += 1; continue
            }
            let asset = Asset(name: dto.name, type: assetType, balance: Decimal(dto.balance),
                             icon: dto.icon, colorHex: dto.colorHex, note: dto.note)
            if let id = UUID(uuidString: dto.id) { asset.id = id }
            asset.isArchived = dto.isArchived
            modelContext.insert(asset)
            result.assetsImported += 1
        }

        // 4. 导入实物资产
        let existingPhysical = (try? modelContext.fetch(FetchDescriptor<PhysicalAsset>())) ?? []
        let existingPhysicalIDs = Set(existingPhysical.map { $0.id.uuidString })

        for dto in backup.physicalAssets {
            if existingPhysicalIDs.contains(dto.id) {
                result.skipped += 1; continue
            }
            guard let cat = PhysicalAssetCategory(rawValue: dto.category) else {
                result.skipped += 1; continue
            }
            let asset = PhysicalAsset(name: dto.name, category: cat,
                                     purchasePrice: Decimal(dto.purchasePrice),
                                     purchaseDate: dto.purchaseDate,
                                     salvageValue: Decimal(dto.salvageValue),
                                     targetDailyCost: Decimal(dto.targetDailyCost),
                                     note: dto.note)
            if let id = UUID(uuidString: dto.id) { asset.id = id }
            asset.isArchived = dto.isArchived
            asset.soldPrice = dto.soldPrice.map { Decimal($0) }
            asset.soldDate = dto.soldDate
            modelContext.insert(asset)
            result.physicalAssetsImported += 1
        }

        // 5. 导入周期规则
        let existingRules = (try? modelContext.fetch(FetchDescriptor<RecurringRule>())) ?? []
        let existingRuleIDs = Set(existingRules.map { $0.id.uuidString })

        for dto in backup.recurringRules {
            if existingRuleIDs.contains(dto.id) {
                result.skipped += 1; continue
            }
            guard let freq = RecurringFrequency(rawValue: dto.frequency) else {
                result.skipped += 1; continue
            }
            let rule = RecurringRule(title: dto.title, amount: Decimal(dto.amount),
                                   isExpense: dto.isExpense, frequency: freq,
                                   nextDueDate: dto.nextDueDate, note: dto.note,
                                   category: dto.categoryId.flatMap { categoryMap[$0] },
                                   ledger: dto.ledgerId.flatMap { ledgerMap[$0] })
            if let id = UUID(uuidString: dto.id) { rule.id = id }
            rule.isActive = dto.isActive
            modelContext.insert(rule)
            result.recurringRulesImported += 1
        }

        // 6. 导入预算
        let existingBudgets = (try? modelContext.fetch(FetchDescriptor<Budget>())) ?? []
        let existingBudgetIDs = Set(existingBudgets.map { $0.id.uuidString })

        for dto in backup.budgets {
            if existingBudgetIDs.contains(dto.id) {
                result.skipped += 1; continue
            }
            let budget = Budget(monthlyLimit: Decimal(dto.monthlyLimit),
                               year: dto.year, month: dto.month,
                               ledger: dto.ledgerId.flatMap { ledgerMap[$0] },
                               categoryId: dto.categoryId.flatMap { UUID(uuidString: $0) })
            if let id = UUID(uuidString: dto.id) { budget.id = id }
            modelContext.insert(budget)
            result.budgetsImported += 1
        }

        try modelContext.save()
        return result
    }
}
