import Foundation
import SwiftData

/// 精确的金额编解码 — JSON 中存字符串（如 "9.99"），但兼容旧版 Double 数值
struct CodableMoney: Codable {
    let value: String

    init(_ decimal: Decimal) {
        self.value = NSDecimalNumber(decimal: decimal).stringValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self.value = str
        } else {
            let num = try container.decode(Double.self)
            self.value = NSDecimalNumber(value: num).stringValue
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    var decimalValue: Decimal { Decimal(string: value) ?? 0 }
}

/// 数据备份/恢复服务 — 全量备份所有数据
@MainActor
final class DataBackupService {

    nonisolated static let currentBackupVersion = "1.6.0"
    nonisolated static let minimumSupportedBackupVersion = "1.0.0"

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    enum ImportError: LocalizedError {
        case invalidVersion(String)
        case unsupportedVersion(String)

        var errorDescription: String? {
            switch self {
            case .invalidVersion(let version):
                return "无法识别备份版本：\(version)"
            case .unsupportedVersion(let version):
                return "不支持备份版本 \(version)，当前支持 \(minimumSupportedBackupVersion) 至 \(currentBackupVersion)"
            }
        }
    }

    private struct SemanticVersion: Comparable {
        let major: Int
        let minor: Int
        let patch: Int

        init?(_ rawValue: String) {
            let parts = rawValue.split(separator: ".", omittingEmptySubsequences: false)
            guard (2...3).contains(parts.count),
                  let major = Int(parts[0]),
                  let minor = Int(parts[1]) else {
                return nil
            }
            let patch: Int
            if parts.count == 3 {
                guard let parsedPatch = Int(parts[2]) else { return nil }
                patch = parsedPatch
            } else {
                patch = 0
            }
            guard major >= 0, minor >= 0, patch >= 0 else { return nil }
            self.major = major
            self.minor = minor
            self.patch = patch
        }

        static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
            (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
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
        let cashPoolItems: [CashPoolItemDTO]
        let cashPoolStates: [CashPoolStateDTO]
        let installmentBills: [InstallmentBillDTO]
        let savingsGoals: [SavingsGoalDTO]
        let templates: [TransactionTemplateDTO]
        let reminders: [ReminderItem]
        let settings: SettingsDTO?

        init(
            version: String,
            createdAt: Date,
            categories: [CategoryDTO],
            ledgers: [LedgerDTO],
            transactions: [TransactionDTO],
            assets: [AssetDTO],
            physicalAssets: [PhysicalAssetDTO],
            recurringRules: [RecurringRuleDTO],
            budgets: [BudgetDTO],
            cashPoolItems: [CashPoolItemDTO],
            cashPoolStates: [CashPoolStateDTO],
            installmentBills: [InstallmentBillDTO],
            savingsGoals: [SavingsGoalDTO],
            templates: [TransactionTemplateDTO],
            reminders: [ReminderItem],
            settings: SettingsDTO?
        ) {
            self.version = version
            self.createdAt = createdAt
            self.categories = categories
            self.ledgers = ledgers
            self.transactions = transactions
            self.assets = assets
            self.physicalAssets = physicalAssets
            self.recurringRules = recurringRules
            self.budgets = budgets
            self.cashPoolItems = cashPoolItems
            self.cashPoolStates = cashPoolStates
            self.installmentBills = installmentBills
            self.savingsGoals = savingsGoals
            self.templates = templates
            self.reminders = reminders
            self.settings = settings
        }

        enum CodingKeys: String, CodingKey {
            case version, createdAt, categories, ledgers, transactions, assets, physicalAssets, recurringRules, budgets
            case cashPoolItems, cashPoolStates, installmentBills, savingsGoals, templates, reminders, settings
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(String.self, forKey: .version)
            createdAt = try container.decode(Date.self, forKey: .createdAt)
            categories = try container.decodeIfPresent([CategoryDTO].self, forKey: .categories) ?? []
            ledgers = try container.decodeIfPresent([LedgerDTO].self, forKey: .ledgers) ?? []
            transactions = try container.decodeIfPresent([TransactionDTO].self, forKey: .transactions) ?? []
            assets = try container.decodeIfPresent([AssetDTO].self, forKey: .assets) ?? []
            physicalAssets = try container.decodeIfPresent([PhysicalAssetDTO].self, forKey: .physicalAssets) ?? []
            recurringRules = try container.decodeIfPresent([RecurringRuleDTO].self, forKey: .recurringRules) ?? []
            budgets = try container.decodeIfPresent([BudgetDTO].self, forKey: .budgets) ?? []
            cashPoolItems = try container.decodeIfPresent([CashPoolItemDTO].self, forKey: .cashPoolItems) ?? []
            cashPoolStates = try container.decodeIfPresent([CashPoolStateDTO].self, forKey: .cashPoolStates) ?? []
            installmentBills = try container.decodeIfPresent([InstallmentBillDTO].self, forKey: .installmentBills) ?? []
            savingsGoals = try container.decodeIfPresent([SavingsGoalDTO].self, forKey: .savingsGoals) ?? []
            templates = try container.decodeIfPresent([TransactionTemplateDTO].self, forKey: .templates) ?? []
            reminders = try container.decodeIfPresent([ReminderItem].self, forKey: .reminders) ?? []
            settings = try container.decodeIfPresent(SettingsDTO.self, forKey: .settings)
        }
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
        let amount: CodableMoney
        let isExpense: Bool
        let note: String
        let date: Date
        let createdAt: Date
        let categoryId: String?
        let ledgerId: String?
        let isPrivateIncome: Bool?
        let cashPoolDelta: CodableMoney?
    }

    struct AssetDTO: Codable {
        let id: String
        let name: String
        let type: String
        let balance: CodableMoney
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
        let purchasePrice: CodableMoney
        let purchaseDate: Date
        let salvageValue: CodableMoney
        let targetDailyCost: CodableMoney
        let soldPrice: CodableMoney?
        let soldDate: Date?
        let note: String
        let isArchived: Bool
    }

    struct RecurringRuleDTO: Codable {
        let id: String
        let title: String
        let amount: CodableMoney
        let isExpense: Bool
        let frequency: String
        let nextDueDate: Date
        let anchorDay: Int?
        let endDate: Date?
        let isActive: Bool
        let note: String
        let createdAt: Date
        let categoryId: String?
        let ledgerId: String?
    }

    struct BudgetDTO: Codable {
        let id: String
        let monthlyLimit: CodableMoney
        let year: Int
        let month: Int
        let createdAt: Date
        let ledgerId: String?
        let categoryId: String?
    }

    struct CashPoolItemDTO: Codable {
        let id: String
        let name: String
        let kind: String
        let amount: CodableMoney
        let note: String
        let isArchived: Bool
        let sortOrder: Int
        let createdAt: Date
        let updatedAt: Date
    }

    struct CashPoolStateDTO: Codable {
        let id: String
        let transactionDelta: CodableMoney
        let updatedAt: Date
    }

    struct InstallmentBillDTO: Codable {
        let id: String
        let name: String
        let totalAmount: CodableMoney
        let installmentCount: Int
        let paidInstallments: Int
        let repaymentDay: Int
        let firstRepaymentDate: Date
        let note: String
        let isArchived: Bool
        let createdAt: Date
        let updatedAt: Date
    }

    struct SavingsGoalDTO: Codable {
        let id: String
        let name: String
        let targetAmount: CodableMoney
        let currentAmount: CodableMoney
        let targetDate: Date?
        let note: String
        let isCompleted: Bool
        let isArchived: Bool
        let createdAt: Date
        let updatedAt: Date
    }

    struct TransactionTemplateDTO: Codable {
        let id: String
        let name: String
        let amount: CodableMoney
        let isExpense: Bool
        let note: String
        let categoryName: String?
        let sortOrder: Int
    }

    struct SettingsDTO: Codable {
        let payday: Int
        let appearance: String?
        let hideAssetBalance: Bool?
        let hasCompletedOnboarding: Bool?

        init(payday: Int, appearance: String?, hideAssetBalance: Bool?, hasCompletedOnboarding: Bool?) {
            self.payday = payday
            self.appearance = appearance
            self.hideAssetBalance = hideAssetBalance
            self.hasCompletedOnboarding = hasCompletedOnboarding
        }
    }

    enum ImportMode { case merge, replace }

    struct BackupPreview {
        let version: String
        let createdAt: Date
        let itemCount: Int
        let reminderCount: Int

        var summary: String {
            "备份版本 \(version)，包含 \(itemCount) 条业务数据、\(reminderCount) 条提醒"
        }
    }

    // MARK: - 导出

    func exportJSON() throws -> Data {
        let categories = try modelContext.fetch(FetchDescriptor<Category>())
        let ledgers = try modelContext.fetch(FetchDescriptor<Ledger>())
        let transactions = try modelContext.fetch(FetchDescriptor<Transaction>())
        let assets = try modelContext.fetch(FetchDescriptor<Asset>())
        let physicalAssets = try modelContext.fetch(FetchDescriptor<PhysicalAsset>())
        let recurringRules = try modelContext.fetch(FetchDescriptor<RecurringRule>())
        let budgets = try modelContext.fetch(FetchDescriptor<Budget>())
        let cashPoolItems = try modelContext.fetch(FetchDescriptor<CashPoolItem>())
        let cashPoolStates = try modelContext.fetch(FetchDescriptor<CashPoolState>())
        let installmentBills = try modelContext.fetch(FetchDescriptor<InstallmentBill>())
        let savingsGoals = try modelContext.fetch(FetchDescriptor<SavingsGoal>())
        let templates = try modelContext.fetch(FetchDescriptor<TransactionTemplate>())
        let reminders = ReminderStore.load()

        let backup = BackupData(
            version: Self.currentBackupVersion,
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
                TransactionDTO(id: t.id.uuidString, amount: CodableMoney(t.amount),
                              isExpense: t.isExpense, note: t.note, date: t.date,
                              createdAt: t.createdAt,
                              categoryId: t.category?.id.uuidString,
                              ledgerId: t.ledger?.id.uuidString,
                              isPrivateIncome: t.isPrivateIncome,
                              cashPoolDelta: t.cashPoolDelta.map { CodableMoney($0) })
            },
            assets: assets.map { a in
                AssetDTO(id: a.id.uuidString, name: a.name, type: a.type.rawValue,
                        balance: CodableMoney(a.balance),
                        icon: a.icon, colorHex: a.colorHex, note: a.note,
                        isArchived: a.isArchived, updatedAt: a.updatedAt,
                        createdAt: a.createdAt)
            },
            physicalAssets: physicalAssets.map { a in
                PhysicalAssetDTO(id: a.id.uuidString, name: a.name,
                                category: a.category.rawValue,
                                purchasePrice: CodableMoney(a.purchasePrice),
                                purchaseDate: a.purchaseDate,
                                salvageValue: CodableMoney(a.salvageValue),
                                targetDailyCost: CodableMoney(a.targetDailyCost),
                                soldPrice: a.soldPrice.map { CodableMoney($0) },
                                soldDate: a.soldDate, note: a.note,
                                isArchived: a.isArchived)
            },
            recurringRules: recurringRules.map { r in
                RecurringRuleDTO(id: r.id.uuidString, title: r.title,
                                amount: CodableMoney(r.amount),
                                isExpense: r.isExpense, frequency: r.frequency.rawValue,
                                nextDueDate: r.nextDueDate, anchorDay: r.anchorDay,
                                endDate: r.endDate, isActive: r.isActive,
                                note: r.note, createdAt: r.createdAt,
                                categoryId: r.category?.id.uuidString,
                                ledgerId: r.ledger?.id.uuidString)
            },
            budgets: budgets.map { b in
                BudgetDTO(id: b.id.uuidString,
                         monthlyLimit: CodableMoney(b.monthlyLimit),
                         year: b.year, month: b.month, createdAt: b.createdAt,
                         ledgerId: b.ledger?.id.uuidString,
                         categoryId: b.categoryId?.uuidString)
            },
            cashPoolItems: cashPoolItems.map { item in
                CashPoolItemDTO(id: item.id.uuidString, name: item.name, kind: item.kind.rawValue,
                                amount: CodableMoney(item.amount),
                                note: item.note, isArchived: item.isArchived,
                                sortOrder: item.sortOrder, createdAt: item.createdAt,
                                updatedAt: item.updatedAt)
            },
            cashPoolStates: cashPoolStates.map { state in
                CashPoolStateDTO(id: state.id.uuidString,
                                 transactionDelta: CodableMoney(state.transactionDelta),
                                 updatedAt: state.updatedAt)
            },
            installmentBills: installmentBills.map { bill in
                InstallmentBillDTO(id: bill.id.uuidString, name: bill.name,
                                   totalAmount: CodableMoney(bill.totalAmount),
                                   installmentCount: bill.installmentCount,
                                   paidInstallments: bill.paidInstallments,
                                   repaymentDay: bill.repaymentDay,
                                   firstRepaymentDate: bill.firstRepaymentDate,
                                   note: bill.note, isArchived: bill.isArchived,
                                   createdAt: bill.createdAt, updatedAt: bill.updatedAt)
            },
            savingsGoals: savingsGoals.map { goal in
                SavingsGoalDTO(id: goal.id.uuidString, name: goal.name,
                               targetAmount: CodableMoney(goal.targetAmount),
                               currentAmount: CodableMoney(goal.currentAmount),
                               targetDate: goal.targetDate, note: goal.note,
                               isCompleted: goal.isCompleted, isArchived: goal.isArchived,
                               createdAt: goal.createdAt, updatedAt: goal.updatedAt)
            },
            templates: templates.map { t in
                TransactionTemplateDTO(id: t.id.uuidString, name: t.name,
                                       amount: CodableMoney(t.amount),
                                       isExpense: t.isExpense, note: t.note,
                                       categoryName: t.categoryName, sortOrder: t.sortOrder)
            },
            reminders: reminders,
            settings: SettingsDTO(
                payday: max(UserDefaults.standard.integer(forKey: "payday"), 1),
                appearance: UserDefaults.standard.string(forKey: "appearance"),
                hideAssetBalance: UserDefaults.standard.object(forKey: "hideAssetBalance") as? Bool,
                hasCompletedOnboarding: UserDefaults.standard.object(forKey: "hasCompletedOnboarding") as? Bool
            )
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
        var cashPoolItemsImported = 0
        var installmentBillsImported = 0
        var savingsGoalsImported = 0
        var templatesImported = 0
        var remindersImported = 0
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
            if cashPoolItemsImported > 0 { parts.append("资金池 \(cashPoolItemsImported)") }
            if installmentBillsImported > 0 { parts.append("分期账单 \(installmentBillsImported)") }
            if savingsGoalsImported > 0 { parts.append("储蓄目标 \(savingsGoalsImported)") }
            if templatesImported > 0 { parts.append("记账模板 \(templatesImported)") }
            if remindersImported > 0 { parts.append("提醒 \(remindersImported)") }

            let importedStr = parts.isEmpty ? "无新数据" : "导入：" + parts.joined(separator: "、")
            let skippedStr = skipped > 0 ? "\n跳过 \(skipped) 项已有数据" : ""
            return importedStr + skippedStr
        }
    }

    func previewJSON(from url: URL) throws -> BackupPreview {
        let data = try Data(contentsOf: url)
        return try previewJSON(data: data)
    }

    func previewJSON(data: Data) throws -> BackupPreview {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(BackupData.self, from: data)
        try Self.validateVersion(backup.version)
        let count = backup.categories.count + backup.ledgers.count + backup.transactions.count + backup.assets.count
            + backup.physicalAssets.count + backup.recurringRules.count + backup.budgets.count + backup.cashPoolItems.count
            + backup.cashPoolStates.count + backup.installmentBills.count + backup.savingsGoals.count + backup.templates.count
        return BackupPreview(version: backup.version, createdAt: backup.createdAt, itemCount: count, reminderCount: backup.reminders.count)
    }

    func importJSON(from url: URL, mode: ImportMode = .merge) throws -> ImportResult {
        let data = try Data(contentsOf: url)
        return try importJSON(data: data, mode: mode)
    }

    func importJSON(data: Data, mode: ImportMode = .merge) throws -> ImportResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(BackupData.self, from: data)
        try Self.validateVersion(backup.version)
        let storedReminders = ReminderStore.load()
        var result = ImportResult()

        do {
            if mode == .replace {
                try deleteAllPersistedModels()
            }

        // 1. 先导入分类和账本（它们被其他模型引用）
        let existingCategories = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<Category>())
        let existingCategoryIDs = Set(existingCategories.map { $0.id.uuidString })
        // 按「名称+收支类型」建立去重索引
        let existingCategoryNames = Dictionary(
            existingCategories.map { ("\($0.name)_\($0.isExpense)", $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var categoryMap: [String: Category] = [:]
        // 建立已有映射
        for c in existingCategories { categoryMap[c.id.uuidString] = c }

        for dto in backup.categories {
            // 按 UUID 去重
            if existingCategoryIDs.contains(dto.id) {
                result.skipped += 1
                continue
            }
            // 按名称+收支类型去重：已有同名分类则复用
            let nameKey = "\(dto.name)_\(dto.isExpense)"
            if let existing = existingCategoryNames[nameKey] {
                categoryMap[dto.id] = existing
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

        let existingLedgers = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<Ledger>())
        let existingLedgerIDs = Set(existingLedgers.map { $0.id.uuidString })
        // 按名称建立去重索引
        let existingLedgerNames = Dictionary(
            existingLedgers.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var ledgerMap: [String: Ledger] = [:]
        for l in existingLedgers { ledgerMap[l.id.uuidString] = l }

        for dto in backup.ledgers {
            // 按 UUID 去重
            if existingLedgerIDs.contains(dto.id) {
                result.skipped += 1
                continue
            }
            // 按名称去重：已有同名账本则复用
            if let existing = existingLedgerNames[dto.name] {
                ledgerMap[dto.id] = existing
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
        let existingTransactions = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<Transaction>())
        let existingTransIDs = Set(existingTransactions.map { $0.id.uuidString })
        var importedTransactionDelta: Decimal = 0

        // 找到默认账本，作为无归属交易的 fallback；旧备份没有账本时就地补建。
        let defaultLedger: Ledger
        if let existing = ledgerMap.values.first(where: { $0.isDefault }) ?? ledgerMap.values.first {
            defaultLedger = existing
        } else {
            let created = Ledger.defaultLedgers()[0]
            modelContext.insert(created)
            ledgerMap[created.id.uuidString] = created
            defaultLedger = created
        }

        for dto in backup.transactions {
            if existingTransIDs.contains(dto.id) {
                result.skipped += 1
                continue
            }
            // 如果 ledgerId 匹配不到已有账本，则归入默认账本
            let matchedLedger = dto.ledgerId.flatMap { ledgerMap[$0] } ?? defaultLedger
            let t = Transaction(amount: dto.amount.decimalValue, isExpense: dto.isExpense,
                               note: dto.note, date: dto.date,
                               isPrivateIncome: dto.isPrivateIncome ?? false,
                               cashPoolDelta: dto.cashPoolDelta?.decimalValue,
                               category: dto.categoryId.flatMap { categoryMap[$0] },
                               ledger: matchedLedger)
            if let id = UUID(uuidString: dto.id) { t.id = id }
            modelContext.insert(t)
            importedTransactionDelta += dto.cashPoolDelta?.decimalValue ?? CashPoolService.transactionDelta(for: t)
            result.transactionsImported += 1
        }

        // 3. 导入资产账户
        let existingAssets = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<Asset>())
        let existingAssetIDs = Set(existingAssets.map { $0.id.uuidString })

        for dto in backup.assets {
            if existingAssetIDs.contains(dto.id) {
                result.skipped += 1
                continue
            }
            guard let assetType = AssetType(rawValue: dto.type) else {
                result.skipped += 1; continue
            }
            let asset = Asset(name: dto.name, type: assetType, balance: dto.balance.decimalValue,
                             icon: dto.icon, colorHex: dto.colorHex, note: dto.note)
            if let id = UUID(uuidString: dto.id) { asset.id = id }
            asset.isArchived = dto.isArchived
            modelContext.insert(asset)
            result.assetsImported += 1
        }

        // 4. 导入实物资产
        let existingPhysical = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<PhysicalAsset>())
        let existingPhysicalIDs = Set(existingPhysical.map { $0.id.uuidString })

        for dto in backup.physicalAssets {
            if existingPhysicalIDs.contains(dto.id) {
                result.skipped += 1; continue
            }
            guard let cat = PhysicalAssetCategory(rawValue: dto.category) else {
                result.skipped += 1; continue
            }
            let asset = PhysicalAsset(name: dto.name, category: cat,
                                     purchasePrice: dto.purchasePrice.decimalValue,
                                     purchaseDate: dto.purchaseDate,
                                     salvageValue: dto.salvageValue.decimalValue,
                                     targetDailyCost: dto.targetDailyCost.decimalValue,
                                     note: dto.note)
            if let id = UUID(uuidString: dto.id) { asset.id = id }
            asset.isArchived = dto.isArchived
            asset.soldPrice = dto.soldPrice?.decimalValue
            asset.soldDate = dto.soldDate
            modelContext.insert(asset)
            result.physicalAssetsImported += 1
        }

        // 5. 导入周期规则
        let existingRules = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<RecurringRule>())
        let existingRuleIDs = Set(existingRules.map { $0.id.uuidString })

        for dto in backup.recurringRules {
            if existingRuleIDs.contains(dto.id) {
                result.skipped += 1; continue
            }
            guard let freq = RecurringFrequency(rawValue: dto.frequency) else {
                result.skipped += 1; continue
            }
            let rule = RecurringRule(title: dto.title, amount: dto.amount.decimalValue,
                                   isExpense: dto.isExpense, frequency: freq,
                                   nextDueDate: dto.nextDueDate, endDate: dto.endDate, note: dto.note,
                                   category: dto.categoryId.flatMap { categoryMap[$0] },
                                   ledger: dto.ledgerId.flatMap { ledgerMap[$0] })
            if let id = UUID(uuidString: dto.id) { rule.id = id }
            rule.anchorDay = dto.anchorDay ?? rule.anchorDay
            rule.isActive = dto.isActive
            modelContext.insert(rule)
            result.recurringRulesImported += 1
        }

        // 6. 导入预算
        let existingBudgets = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<Budget>())
        let existingBudgetIDs = Set(existingBudgets.map { $0.id.uuidString })

        for dto in backup.budgets {
            if existingBudgetIDs.contains(dto.id) {
                result.skipped += 1; continue
            }
            let budget = Budget(monthlyLimit: dto.monthlyLimit.decimalValue,
                               year: dto.year, month: dto.month,
                               ledger: dto.ledgerId.flatMap { ledgerMap[$0] },
                               categoryId: dto.categoryId.flatMap { UUID(uuidString: $0) })
            if let id = UUID(uuidString: dto.id) { budget.id = id }
            modelContext.insert(budget)
            result.budgetsImported += 1
        }

        // 7. 导入资金池
        let existingCashItems = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<CashPoolItem>())
        let existingCashItemIDs = Set(existingCashItems.map { $0.id.uuidString })

        for dto in backup.cashPoolItems {
            if existingCashItemIDs.contains(dto.id) {
                result.skipped += 1; continue
            }
            guard let kind = CashPoolItemKind(rawValue: dto.kind) else {
                result.skipped += 1; continue
            }
            let item = CashPoolItem(
                name: dto.name,
                kind: kind,
                amount: dto.amount.decimalValue,
                note: dto.note,
                sortOrder: dto.sortOrder
            )
            if let id = UUID(uuidString: dto.id) { item.id = id }
            item.isArchived = dto.isArchived
            item.createdAt = dto.createdAt
            item.updatedAt = dto.updatedAt
            modelContext.insert(item)
            result.cashPoolItemsImported += 1
        }

        let existingCashStates = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<CashPoolState>())
        if existingCashStates.isEmpty, let dto = backup.cashPoolStates.max(by: { $0.updatedAt < $1.updatedAt }) {
            let state = CashPoolState(transactionDelta: dto.transactionDelta.decimalValue)
            if let id = UUID(uuidString: dto.id) { state.id = id }
            state.updatedAt = dto.updatedAt
            modelContext.insert(state)
        } else if !existingCashStates.isEmpty {
            // A merge keeps the local state and incorporates only newly
            // imported transactions. Importing a second state would make the
            // balance source non-deterministic.
            CashPoolService(modelContext: modelContext).applyImportedTransactionDeltas(importedTransactionDelta)
            result.skipped += backup.cashPoolStates.count
        } else if importedTransactionDelta != 0 {
            CashPoolService(modelContext: modelContext).applyImportedTransactionDeltas(importedTransactionDelta)
        }

        // 8. 导入分期账单
        let existingInstallmentBills = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<InstallmentBill>())
        let existingInstallmentBillIDs = Set(existingInstallmentBills.map { $0.id.uuidString })

        for dto in backup.installmentBills {
            if existingInstallmentBillIDs.contains(dto.id) {
                result.skipped += 1; continue
            }
            let bill = InstallmentBill(
                name: dto.name,
                totalAmount: dto.totalAmount.decimalValue,
                installmentCount: dto.installmentCount,
                paidInstallments: dto.paidInstallments,
                repaymentDay: dto.repaymentDay,
                firstRepaymentDate: dto.firstRepaymentDate,
                note: dto.note
            )
            if let id = UUID(uuidString: dto.id) { bill.id = id }
            bill.isArchived = dto.isArchived
            bill.createdAt = dto.createdAt
            bill.updatedAt = dto.updatedAt
            modelContext.insert(bill)
            result.installmentBillsImported += 1
        }

        // 9. 导入储蓄目标
        let existingSavingsGoals = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<SavingsGoal>())
        let existingSavingsGoalIDs = Set(existingSavingsGoals.map { $0.id.uuidString })

        for dto in backup.savingsGoals {
            if existingSavingsGoalIDs.contains(dto.id) {
                result.skipped += 1; continue
            }
            let goal = SavingsGoal(
                name: dto.name,
                targetAmount: dto.targetAmount.decimalValue,
                currentAmount: dto.currentAmount.decimalValue,
                targetDate: dto.targetDate,
                note: dto.note
            )
            if let id = UUID(uuidString: dto.id) { goal.id = id }
            goal.isCompleted = dto.isCompleted
            goal.isArchived = dto.isArchived
            goal.createdAt = dto.createdAt
            goal.updatedAt = dto.updatedAt
            modelContext.insert(goal)
            result.savingsGoalsImported += 1
        }

        // 10. 导入记账模板
        let existingTemplates = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<TransactionTemplate>())
        let existingTemplateIDs = Set(existingTemplates.map { $0.id.uuidString })

        for dto in backup.templates {
            if existingTemplateIDs.contains(dto.id) {
                result.skipped += 1; continue
            }
            let template = TransactionTemplate(
                name: dto.name,
                amount: dto.amount.decimalValue,
                isExpense: dto.isExpense,
                note: dto.note,
                categoryName: dto.categoryName,
                sortOrder: dto.sortOrder
            )
            if let id = UUID(uuidString: dto.id) { template.id = id }
            modelContext.insert(template)
            result.templatesImported += 1
        }

            // 默认数据、单账本整理与本次恢复共用一次数据库事务。
            try DefaultDataService(modelContext: modelContext).stageDefaultData()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        let localReminders = mode == .replace ? [] : storedReminders
        let localReminderIDs = Set(localReminders.map(\.id))
        let newReminders = backup.reminders.filter { !localReminderIDs.contains($0.id) }
        let importedReminders = localReminders + newReminders

        if mode == .replace || !newReminders.isEmpty {
            try ReminderStore.replace(with: importedReminders)
            result.remindersImported = newReminders.count
            Task {
                if mode == .replace {
                    for reminder in storedReminders {
                        ReminderNotificationService.cancel(reminderID: reminder.id)
                    }
                }
                for reminder in newReminders where !reminder.isCompleted {
                    try? await ReminderNotificationService.schedule(reminder)
                }
            }
        }

        if let settings = backup.settings {
            UserDefaults.standard.set(min(max(settings.payday, 1), 31), forKey: "payday")
            if let appearance = settings.appearance { UserDefaults.standard.set(appearance, forKey: "appearance") }
            if let hideAssetBalance = settings.hideAssetBalance { UserDefaults.standard.set(hideAssetBalance, forKey: "hideAssetBalance") }
            if let hasCompletedOnboarding = settings.hasCompletedOnboarding { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
        }
        return result
    }

    private static func validateVersion(_ rawVersion: String) throws {
        guard let version = SemanticVersion(rawVersion),
              let minimum = SemanticVersion(minimumSupportedBackupVersion),
              let current = SemanticVersion(currentBackupVersion) else {
            throw ImportError.invalidVersion(rawVersion)
        }
        guard version >= minimum, version <= current else {
            throw ImportError.unsupportedVersion(rawVersion)
        }
    }

    private func deleteAllPersistedModels() throws {
        try deleteAll(Transaction.self); try deleteAll(Category.self); try deleteAll(Ledger.self)
        try deleteAll(RecurringRule.self); try deleteAll(Budget.self); try deleteAll(Asset.self)
        try deleteAll(PhysicalAsset.self); try deleteAll(CashPoolItem.self); try deleteAll(CashPoolState.self)
        try deleteAll(SavingsGoal.self); try deleteAll(InstallmentBill.self); try deleteAll(TransactionTemplate.self)
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        for item in try modelContext.fetch(FetchDescriptor<T>()) { modelContext.delete(item) }
    }
}
