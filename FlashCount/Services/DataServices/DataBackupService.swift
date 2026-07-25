import Foundation
import SwiftData

/// 精确的金额编解码 — JSON 中存字符串（如 "9.99"），但兼容旧版 Double 数值
struct CodableMoney: Codable {
    let value: String
    let decimalValue: Decimal

    init(_ decimal: Decimal) {
        self.value = NSDecimalNumber(decimal: decimal).stringValue
        self.decimalValue = decimal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            guard let decimal = Decimal(string: str), decimal.isFinite else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "无效金额：\(str)")
            }
            self.value = str
            self.decimalValue = decimal
        } else {
            let decimal = try container.decode(Decimal.self)
            guard decimal.isFinite else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "金额不是有限数值")
            }
            self.value = NSDecimalNumber(decimal: decimal).stringValue
            self.decimalValue = decimal
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

}

private extension Decimal {
    var isFinite: Bool { !isNaN }
}

/// 数据备份/恢复服务 — 全量备份所有数据
@MainActor
final class DataBackupService {

    nonisolated static let currentBackupVersion = "1.9.0"
    nonisolated static let minimumSupportedBackupVersion = "1.0.0"

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    enum ImportError: LocalizedError {
        case invalidVersion(String)
        case unsupportedVersion(String)
        case invalidContents(String)

        var errorDescription: String? {
            switch self {
            case .invalidVersion(let version):
                return "无法识别备份版本：\(version)"
            case .unsupportedVersion(let version):
                return "不支持备份版本 \(version)，当前支持 \(minimumSupportedBackupVersion) 至 \(currentBackupVersion)"
            case .invalidContents(let message):
                return "备份内容无效：\(message)"
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
        let recurringOccurrences: [RecurringOccurrenceDTO]
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
            recurringOccurrences: [RecurringOccurrenceDTO] = [],
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
            self.recurringOccurrences = recurringOccurrences
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
            case version, createdAt, categories, ledgers, transactions, assets, physicalAssets, recurringRules, recurringOccurrences, budgets
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
            recurringOccurrences = try container.decodeIfPresent([RecurringOccurrenceDTO].self, forKey: .recurringOccurrences) ?? []
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
        let dailyBudgetOverride: Bool?
        let parentCategoryName: String?
        let defaultKey: String?
        let mergedIntoCategoryId: String?
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
        let dailyBudgetOverride: Bool?
        /// Optional for compatibility with backups created before recurring
        /// transaction provenance was persisted.
        let recurringRuleId: String?
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

    struct RecurringOccurrenceDTO: Codable {
        let id: String
        let occurrenceKey: String
        let ruleId: String
        let transactionId: String?
        let scheduledDate: Date
        let actualDate: Date?
        let amount: CodableMoney
        let isExpense: Bool
        let title: String
        let note: String
        let categoryId: String?
        let ledgerId: String?
        let status: String
        let createdAt: Date
        let resolvedAt: Date?
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
        let notificationShowReminderDetails: Bool?
        let reportReminderPreferences: ReportReminderPreferences?
        let recurringCatchUpMode: String?

        init(
            payday: Int,
            appearance: String?,
            hideAssetBalance: Bool?,
            hasCompletedOnboarding: Bool?,
            notificationShowReminderDetails: Bool? = nil,
            reportReminderPreferences: ReportReminderPreferences? = nil,
            recurringCatchUpMode: String? = nil
        ) {
            self.payday = payday
            self.appearance = appearance
            self.hideAssetBalance = hideAssetBalance
            self.hasCompletedOnboarding = hasCompletedOnboarding
            self.notificationShowReminderDetails = notificationShowReminderDetails
            self.reportReminderPreferences = reportReminderPreferences
            self.recurringCatchUpMode = recurringCatchUpMode
        }
    }

    enum ImportMode: String, Codable { case merge, replace }

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
        let recurringOccurrences = try modelContext.fetch(FetchDescriptor<RecurringOccurrence>())
        let budgets = try modelContext.fetch(FetchDescriptor<Budget>())
        let cashPoolItems = try modelContext.fetch(FetchDescriptor<CashPoolItem>())
        let cashPoolStates = try modelContext.fetch(FetchDescriptor<CashPoolState>())
        let installmentBills = try modelContext.fetch(FetchDescriptor<InstallmentBill>())
        let savingsGoals = try modelContext.fetch(FetchDescriptor<SavingsGoal>())
        let templates = try modelContext.fetch(FetchDescriptor<TransactionTemplate>())
        let reminders = try ReminderDataService(modelContext: modelContext).load()

        let backup = BackupData(
            version: Self.currentBackupVersion,
            createdAt: Date(),
            categories: categories.map { c in
                CategoryDTO(id: c.id.uuidString, name: c.name, icon: c.icon,
                           colorHex: c.colorHex, isExpense: c.isExpense,
                           sortOrder: c.sortOrder, isArchived: c.isArchived,
                           dailyBudgetOverride: c.dailyBudgetOverride,
                           parentCategoryName: c.parentCategoryName,
                           defaultKey: c.defaultKey,
                           mergedIntoCategoryId: c.mergedIntoCategoryID?.uuidString)
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
                              cashPoolDelta: t.cashPoolDelta.map { CodableMoney($0) },
                              dailyBudgetOverride: t.dailyBudgetOverride,
                              recurringRuleId: t.recurringRule?.id.uuidString)
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
            recurringOccurrences: recurringOccurrences.map { occurrence in
                RecurringOccurrenceDTO(
                    id: occurrence.id.uuidString,
                    occurrenceKey: occurrence.occurrenceKey,
                    ruleId: occurrence.ruleID.uuidString,
                    transactionId: occurrence.transactionID?.uuidString,
                    scheduledDate: occurrence.scheduledDate,
                    actualDate: occurrence.actualDate,
                    amount: CodableMoney(occurrence.amount),
                    isExpense: occurrence.isExpense,
                    title: occurrence.title,
                    note: occurrence.note,
                    categoryId: occurrence.categoryID?.uuidString,
                    ledgerId: occurrence.ledgerID?.uuidString,
                    status: occurrence.status.rawValue,
                    createdAt: occurrence.createdAt,
                    resolvedAt: occurrence.resolvedAt
                )
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
                hasCompletedOnboarding: UserDefaults.standard.object(forKey: "hasCompletedOnboarding") as? Bool,
                notificationShowReminderDetails: UserDefaults.standard.object(forKey: "notificationShowReminderDetails") as? Bool,
                reportReminderPreferences: UserDefaultsReportReminderPreferencesStore().load(),
                recurringCatchUpMode: UserDefaults.standard.string(forKey: RecurringCatchUpPreferences.storageKey)
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
        var recurringOccurrencesImported = 0
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
            if recurringOccurrencesImported > 0 { parts.append("周期发生项 \(recurringOccurrencesImported)") }
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
            + backup.physicalAssets.count + backup.recurringRules.count + backup.recurringOccurrences.count + backup.budgets.count + backup.cashPoolItems.count
            + backup.cashPoolStates.count + backup.installmentBills.count + backup.savingsGoals.count + backup.templates.count
        return BackupPreview(version: backup.version, createdAt: backup.createdAt, itemCount: count, reminderCount: backup.reminders.count)
    }

    func importJSON(from url: URL, mode: ImportMode = .merge) throws -> ImportResult {
        let data = try Data(contentsOf: url)
        return try importJSON(data: data, mode: mode)
    }

    func importJSON(data: Data, mode: ImportMode = .merge) throws -> ImportResult {
        try importJSON(data: data, mode: mode, recovering: false)
    }

    private func importJSON(data: Data, mode: ImportMode, recovering: Bool) throws -> ImportResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(BackupData.self, from: data)
        try Self.validateVersion(backup.version)
        try Self.validateContents(backup, mode: mode)
        if !recovering {
            try Self.writeImportJournal(backupData: data, mode: mode, phase: .prepared)
        }
        var result = ImportResult()

        do {
            if mode == .replace {
                try deleteAllPersistedModels()
            }

        // 1. 先导入分类和账本（它们被其他模型引用）
        let existingCategories = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<Category>())
        let existingCategoryIDs = Set(existingCategories.map(\.id))
        // 按「名称+收支类型」建立去重索引
        let existingCategoryNames = Dictionary(
            existingCategories.map { ("\($0.name)_\($0.isExpense)", $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var categoryMap: [UUID: Category] = [:]
        // 建立已有映射
        for category in existingCategories { categoryMap[category.id] = category }

        for dto in backup.categories {
            let dtoID = UUID(uuidString: dto.id)!
            // 按 UUID 去重
            if existingCategoryIDs.contains(dtoID) {
                categoryMap[dtoID] = existingCategories.first { $0.id == dtoID }
                result.skipped += 1
                continue
            }
            // 按名称+收支类型去重：已有同名分类则复用
            let nameKey = "\(dto.name)_\(dto.isExpense)"
            if let existing = existingCategoryNames[nameKey] {
                categoryMap[dtoID] = existing
                result.skipped += 1
                continue
            }
            let cat = Category(
                name: dto.name,
                icon: dto.icon,
                colorHex: dto.colorHex,
                isExpense: dto.isExpense,
                sortOrder: dto.sortOrder,
                parentCategoryName: dto.parentCategoryName,
                defaultKey: dto.defaultKey
            )
            cat.id = dtoID
            cat.isArchived = dto.isArchived
            cat.dailyBudgetOverride = dto.dailyBudgetOverride
            modelContext.insert(cat)
            categoryMap[dtoID] = cat
            result.categoriesImported += 1
        }

        // 同名分类在合并导入时可能会映射到本地 UUID；所有合并关系都必须
        // 指向实际持久化分类，而非备份中的原始 UUID。
        for dto in backup.categories {
            guard let category = categoryMap[UUID(uuidString: dto.id)!] else { continue }
            category.mergedIntoCategoryID = dto.mergedIntoCategoryId
                .flatMap(UUID.init(uuidString:))
                .flatMap { categoryMap[$0]?.id }
        }

        let existingLedgers = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<Ledger>())
        let existingLedgerIDs = Set(existingLedgers.map(\.id))
        // 按名称建立去重索引
        let existingLedgerNames = Dictionary(
            existingLedgers.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var ledgerMap: [UUID: Ledger] = [:]
        for ledger in existingLedgers { ledgerMap[ledger.id] = ledger }

        for dto in backup.ledgers {
            let dtoID = UUID(uuidString: dto.id)!
            // 按 UUID 去重
            if existingLedgerIDs.contains(dtoID) {
                ledgerMap[dtoID] = existingLedgers.first { $0.id == dtoID }
                result.skipped += 1
                continue
            }
            // 按名称去重：已有同名账本则复用
            if let existing = existingLedgerNames[dto.name] {
                ledgerMap[dtoID] = existing
                result.skipped += 1
                continue
            }
            let ledger = Ledger(name: dto.name, icon: dto.icon, colorHex: dto.colorHex,
                               isDefault: dto.isDefault, sortOrder: dto.sortOrder)
            ledger.id = dtoID
            ledger.isArchived = dto.isArchived
            ledger.createdAt = dto.createdAt
            modelContext.insert(ledger)
            ledgerMap[dtoID] = ledger
            result.ledgersImported += 1
        }

        // 2. 导入交易记录
        let existingTransactions = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<Transaction>())
        let existingTransIDs = Set(existingTransactions.map(\.id))
        var transactionMap = Dictionary(uniqueKeysWithValues: existingTransactions.map { ($0.id, $0) })
        var importedTransactionDelta: Decimal = 0
        var pendingRecurringRelationships: [(transaction: Transaction, ruleID: UUID)] = []

        // 找到默认账本，作为无归属交易的 fallback；旧备份没有账本时就地补建。
        let defaultLedger: Ledger
        if let existing = ledgerMap.values.first(where: { $0.isDefault }) ?? ledgerMap.values.first {
            defaultLedger = existing
        } else {
            let created = Ledger.defaultLedgers()[0]
            modelContext.insert(created)
            ledgerMap[created.id] = created
            defaultLedger = created
        }

        for dto in backup.transactions {
            let dtoID = UUID(uuidString: dto.id)!
            if existingTransIDs.contains(dtoID) {
                result.skipped += 1
                continue
            }
            // 如果 ledgerId 匹配不到已有账本，则归入默认账本
            let matchedLedger = dto.ledgerId
                .flatMap(UUID.init(uuidString:))
                .flatMap { ledgerMap[$0] } ?? defaultLedger
            let t = Transaction(amount: dto.amount.decimalValue, isExpense: dto.isExpense,
                               note: dto.note, date: dto.date,
                               isPrivateIncome: dto.isPrivateIncome ?? false,
                               cashPoolDelta: nil,
                               dailyBudgetOverride: dto.dailyBudgetOverride,
                               category: dto.categoryId
                                   .flatMap(UUID.init(uuidString:))
                                   .flatMap { categoryMap[$0] },
                               ledger: matchedLedger)
            t.id = dtoID
            t.createdAt = dto.createdAt
            let cashPoolDelta = dto.cashPoolDelta?.decimalValue ?? CashPoolService.transactionDelta(for: t)
            t.cashPoolDelta = cashPoolDelta
            modelContext.insert(t)
            transactionMap[dtoID] = t
            if let ruleID = dto.recurringRuleId.flatMap(UUID.init(uuidString:)) {
                pendingRecurringRelationships.append((t, ruleID))
            }
            importedTransactionDelta += cashPoolDelta
            result.transactionsImported += 1
        }

        // 3. 导入资产账户
        let existingAssets = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<Asset>())
        let existingAssetIDs = Set(existingAssets.map(\.id))

        for dto in backup.assets {
            let dtoID = UUID(uuidString: dto.id)!
            if existingAssetIDs.contains(dtoID) {
                result.skipped += 1
                continue
            }
            guard let assetType = AssetType(rawValue: dto.type) else {
                result.skipped += 1; continue
            }
            let asset = Asset(name: dto.name, type: assetType, balance: dto.balance.decimalValue,
                             icon: dto.icon, colorHex: dto.colorHex, note: dto.note)
            asset.id = dtoID
            asset.isArchived = dto.isArchived
            asset.createdAt = dto.createdAt
            asset.updatedAt = dto.updatedAt
            modelContext.insert(asset)
            result.assetsImported += 1
        }

        // 4. 导入实物资产
        let existingPhysical = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<PhysicalAsset>())
        let existingPhysicalIDs = Set(existingPhysical.map(\.id))

        for dto in backup.physicalAssets {
            let dtoID = UUID(uuidString: dto.id)!
            if existingPhysicalIDs.contains(dtoID) {
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
            asset.id = dtoID
            asset.isArchived = dto.isArchived
            asset.soldPrice = dto.soldPrice?.decimalValue
            asset.soldDate = dto.soldDate
            modelContext.insert(asset)
            result.physicalAssetsImported += 1
        }

        // 5. 导入周期规则
        let existingRules = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<RecurringRule>())
        let existingRuleIDs = Set(existingRules.map(\.id))
        var ruleMap = Dictionary(uniqueKeysWithValues: existingRules.map { ($0.id, $0) })

        for dto in backup.recurringRules {
            let dtoID = UUID(uuidString: dto.id)!
            if existingRuleIDs.contains(dtoID) {
                result.skipped += 1; continue
            }
            guard let freq = RecurringFrequency(rawValue: dto.frequency) else {
                result.skipped += 1; continue
            }
            let rule = RecurringRule(title: dto.title, amount: dto.amount.decimalValue,
                                   isExpense: dto.isExpense, frequency: freq,
                                   nextDueDate: dto.nextDueDate, endDate: dto.endDate, note: dto.note,
                                   category: dto.categoryId
                                       .flatMap(UUID.init(uuidString:))
                                       .flatMap { categoryMap[$0] },
                                   ledger: dto.ledgerId
                                       .flatMap(UUID.init(uuidString:))
                                       .flatMap { ledgerMap[$0] })
            rule.id = dtoID
            rule.anchorDay = dto.anchorDay ?? rule.anchorDay
            rule.isActive = dto.isActive
            rule.createdAt = dto.createdAt
            modelContext.insert(rule)
            ruleMap[dtoID] = rule
            result.recurringRulesImported += 1
        }

        for relationship in pendingRecurringRelationships {
            relationship.transaction.recurringRule = ruleMap[relationship.ruleID]
        }

        // 6. 导入周期发生项。旧备份没有这一组数据时保持为空；
        // 已有交易与规则通过 UUID 恢复关系，合并导入仍按发生项 ID 去重。
        let existingOccurrences = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<RecurringOccurrence>())
        let existingOccurrenceIDs = Set(existingOccurrences.map(\.id))
        var existingOccurrenceKeys = Set(existingOccurrences.map(\.occurrenceKey))
        for dto in backup.recurringOccurrences {
            let dtoID = UUID(uuidString: dto.id)!
            if existingOccurrenceIDs.contains(dtoID) || existingOccurrenceKeys.contains(dto.occurrenceKey) {
                result.skipped += 1
                continue
            }
            guard let ruleID = UUID(uuidString: dto.ruleId),
                  let rule = ruleMap[ruleID],
                  let status = RecurringOccurrenceStatus(rawValue: dto.status) else {
                result.skipped += 1
                continue
            }
            let occurrence = RecurringOccurrence(
                occurrenceKey: dto.occurrenceKey,
                ruleID: rule.id,
                transactionID: dto.transactionId.flatMap(UUID.init(uuidString:)),
                scheduledDate: dto.scheduledDate,
                actualDate: dto.actualDate,
                amount: dto.amount.decimalValue,
                isExpense: dto.isExpense,
                title: dto.title,
                note: dto.note,
                categoryID: dto.categoryId.flatMap(UUID.init(uuidString:)),
                ledgerID: dto.ledgerId.flatMap(UUID.init(uuidString:)),
                status: status,
                createdAt: dto.createdAt,
                resolvedAt: dto.resolvedAt
            )
            occurrence.id = dtoID
            if let transactionID = occurrence.transactionID, transactionMap[transactionID] == nil {
                occurrence.transactionID = nil
            }
            modelContext.insert(occurrence)
            existingOccurrenceKeys.insert(occurrence.occurrenceKey)
            result.recurringOccurrencesImported += 1
        }

        // 7. 导入预算
        let existingBudgets = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<Budget>())
        let existingBudgetIDs = Set(existingBudgets.map(\.id))

        for dto in backup.budgets {
            let dtoID = UUID(uuidString: dto.id)!
            if existingBudgetIDs.contains(dtoID) {
                result.skipped += 1; continue
            }
            let budget = Budget(monthlyLimit: dto.monthlyLimit.decimalValue,
                               year: dto.year, month: dto.month,
                               ledger: dto.ledgerId
                                   .flatMap(UUID.init(uuidString:))
                                   .flatMap { ledgerMap[$0] },
                               categoryId: dto.categoryId
                                   .flatMap(UUID.init(uuidString:))
                                   .flatMap { categoryMap[$0]?.id })
            budget.id = dtoID
            budget.createdAt = dto.createdAt
            modelContext.insert(budget)
            result.budgetsImported += 1
        }

        // 7. 导入资金池
        let existingCashItems = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<CashPoolItem>())
        let existingCashItemIDs = Set(existingCashItems.map(\.id))

        for dto in backup.cashPoolItems {
            let dtoID = UUID(uuidString: dto.id)!
            if existingCashItemIDs.contains(dtoID) {
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
            item.id = dtoID
            item.isArchived = dto.isArchived
            item.createdAt = dto.createdAt
            item.updatedAt = dto.updatedAt
            modelContext.insert(item)
            result.cashPoolItemsImported += 1
        }

        let existingCashStates = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<CashPoolState>())
        if existingCashStates.isEmpty, let dto = backup.cashPoolStates.max(by: { $0.updatedAt < $1.updatedAt }) {
            let state = CashPoolState(transactionDelta: dto.transactionDelta.decimalValue)
            state.id = UUID(uuidString: dto.id)!
            state.updatedAt = dto.updatedAt
            modelContext.insert(state)
        } else if !existingCashStates.isEmpty {
            // A merge keeps the local state and incorporates only newly
            // imported transactions. Importing a second state would make the
            // balance source non-deterministic.
            try CashPoolService(modelContext: modelContext).applyImportedTransactionDeltas(importedTransactionDelta)
            result.skipped += backup.cashPoolStates.count
        } else if importedTransactionDelta != 0 {
            try CashPoolService(modelContext: modelContext).applyImportedTransactionDeltas(importedTransactionDelta)
        }

        // 8. 导入分期账单
        let existingInstallmentBills = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<InstallmentBill>())
        let existingInstallmentBillIDs = Set(existingInstallmentBills.map(\.id))

        for dto in backup.installmentBills {
            let dtoID = UUID(uuidString: dto.id)!
            if existingInstallmentBillIDs.contains(dtoID) {
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
            bill.id = dtoID
            bill.isArchived = dto.isArchived
            bill.createdAt = dto.createdAt
            bill.updatedAt = dto.updatedAt
            modelContext.insert(bill)
            result.installmentBillsImported += 1
        }

        // 9. 导入储蓄目标
        let existingSavingsGoals = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<SavingsGoal>())
        let existingSavingsGoalIDs = Set(existingSavingsGoals.map(\.id))

        for dto in backup.savingsGoals {
            let dtoID = UUID(uuidString: dto.id)!
            if existingSavingsGoalIDs.contains(dtoID) {
                result.skipped += 1; continue
            }
            let goal = SavingsGoal(
                name: dto.name,
                targetAmount: dto.targetAmount.decimalValue,
                currentAmount: dto.currentAmount.decimalValue,
                targetDate: dto.targetDate,
                note: dto.note
            )
            goal.id = dtoID
            goal.isCompleted = dto.isCompleted
            goal.isArchived = dto.isArchived
            goal.createdAt = dto.createdAt
            goal.updatedAt = dto.updatedAt
            modelContext.insert(goal)
            result.savingsGoalsImported += 1
        }

        // 10. 导入记账模板
        let existingTemplates = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<TransactionTemplate>())
        let existingTemplateIDs = Set(existingTemplates.map(\.id))

        for dto in backup.templates {
            let dtoID = UUID(uuidString: dto.id)!
            if existingTemplateIDs.contains(dtoID) {
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
            template.id = dtoID
            modelContext.insert(template)
            result.templatesImported += 1
        }

        // 11. 导入提醒。提醒与财务模型处于同一个 SwiftData 提交中，
        // 不再依赖独立 JSON 文件的第二次写入。
        let existingReminders = mode == .replace ? [] : try modelContext.fetch(FetchDescriptor<Reminder>())
        let existingReminderIDs = Set(existingReminders.map(\.id))
        for reminder in backup.reminders where !existingReminderIDs.contains(reminder.id) {
            modelContext.insert(Reminder(item: reminder))
            result.remindersImported += 1
        }
        result.skipped += backup.reminders.count - result.remindersImported

        // 默认数据、单账本整理与本次恢复共用一次数据库事务。
        try DefaultDataService(modelContext: modelContext).stageDefaultData()
        try modelContext.save()
        } catch {
            modelContext.rollback()
            try? Self.clearImportJournal()
            throw error
        }

        try Self.writeImportJournal(backupData: data, mode: mode, phase: .databaseCommitted)

        let externalSettingsChanged = try applyExternalSettings(from: backup)
        if mode == .replace {
            ReminderDataService(modelContext: modelContext).markLegacyFileMigrationComplete()
        }
        if mode == .replace || result.remindersImported > 0 || externalSettingsChanged {
            rebuildNotificationSchedule()
        }
        try Self.clearImportJournal()
        return result
    }

    /// Completes an import that was interrupted between its SwiftData and
    /// external-settings commits. Replaying is idempotent because every
    /// imported model is keyed by UUID and replace mode clears before inserting.
    @discardableResult
    func recoverPendingImport() throws -> Bool {
        guard let journal = try Self.readImportJournal() else { return false }
        switch journal.phase {
        case .prepared:
            _ = try importJSON(data: journal.backupData, mode: journal.mode, recovering: true)
        case .databaseCommitted:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let backup = try decoder.decode(BackupData.self, from: journal.backupData)
            // Journals written by earlier app versions committed reminder JSON
            // separately. Merge/replace it here so an interrupted upgrade never
            // loses the reminder payload from that backup.
            _ = try restoreRemindersFromRecoveredImport(backup.reminders, mode: journal.mode)
            _ = try applyExternalSettings(from: backup)
            if journal.mode == .replace {
                ReminderDataService(modelContext: modelContext).markLegacyFileMigrationComplete()
            }
            rebuildNotificationSchedule()
            try Self.clearImportJournal()
        }
        return true
    }

    private enum ImportJournalPhase: String, Codable {
        case prepared
        case databaseCommitted
    }

    private struct ImportJournal: Codable {
        let backupData: Data
        let mode: ImportMode
        let phase: ImportJournalPhase
    }

    private static var importJournalURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent("flashcount-import-journal.json")
    }

    private static func writeImportJournal(backupData: Data, mode: ImportMode, phase: ImportJournalPhase) throws {
        let url = importJournalURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(ImportJournal(backupData: backupData, mode: mode, phase: phase))
        try data.write(to: url, options: .atomic)
    }

    private static func readImportJournal() throws -> ImportJournal? {
        guard FileManager.default.fileExists(atPath: importJournalURL.path) else { return nil }
        return try JSONDecoder().decode(ImportJournal.self, from: Data(contentsOf: importJournalURL))
    }

    private static func clearImportJournal() throws {
        guard FileManager.default.fileExists(atPath: importJournalURL.path) else { return }
        try FileManager.default.removeItem(at: importJournalURL)
    }

    private func applyExternalSettings(from backup: BackupData) throws -> Bool {
        var shouldRebuildNotifications = false
        if let settings = backup.settings {
            UserDefaults.standard.set(min(max(settings.payday, 1), 31), forKey: "payday")
            shouldRebuildNotifications = true
            if let appearance = settings.appearance { UserDefaults.standard.set(appearance, forKey: "appearance") }
            if let hideAssetBalance = settings.hideAssetBalance { UserDefaults.standard.set(hideAssetBalance, forKey: "hideAssetBalance") }
            if let hasCompletedOnboarding = settings.hasCompletedOnboarding { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
            if let notificationShowReminderDetails = settings.notificationShowReminderDetails {
                UserDefaults.standard.set(notificationShowReminderDetails, forKey: "notificationShowReminderDetails")
                shouldRebuildNotifications = true
            }
            if let reportPreferences = settings.reportReminderPreferences {
                try UserDefaultsReportReminderPreferencesStore().save(reportPreferences)
                shouldRebuildNotifications = true
            }
            if let recurringCatchUpMode = settings.recurringCatchUpMode,
               RecurringCatchUpMode(rawValue: recurringCatchUpMode) != nil {
                UserDefaults.standard.set(recurringCatchUpMode, forKey: RecurringCatchUpPreferences.storageKey)
            }
        }
        return shouldRebuildNotifications
    }

    private static func validateContents(_ backup: BackupData, mode: ImportMode) throws {
        try validateUniqueIDs(backup.categories.map(\.id), label: "分类")
        try validateUniqueIDs(backup.ledgers.map(\.id), label: "账本")
        try validateUniqueIDs(backup.transactions.map(\.id), label: "账单")
        try validateUniqueIDs(backup.assets.map(\.id), label: "账户")
        try validateUniqueIDs(backup.physicalAssets.map(\.id), label: "实物资产")
        try validateUniqueIDs(backup.recurringRules.map(\.id), label: "周期规则")
        try validateUniqueIDs(backup.recurringOccurrences.map(\.id), label: "周期发生项")
        try validateUniqueIDs(backup.budgets.map(\.id), label: "预算")
        try validateUniqueIDs(backup.cashPoolItems.map(\.id), label: "资金项")
        try validateUniqueIDs(backup.cashPoolStates.map(\.id), label: "资金状态")
        try validateUniqueIDs(backup.installmentBills.map(\.id), label: "分期")
        try validateUniqueIDs(backup.savingsGoals.map(\.id), label: "储蓄目标")
        try validateUniqueIDs(backup.templates.map(\.id), label: "模板")
        try validateUniqueIDs(backup.reminders.map { $0.id.uuidString }, label: "提醒")

        guard backup.transactions.allSatisfy({ $0.amount.decimalValue > 0 }) else {
            throw ImportError.invalidContents("账单金额必须大于零")
        }
        guard backup.assets.allSatisfy({ $0.balance.decimalValue >= 0 }) else {
            throw ImportError.invalidContents("账户余额不能为负数")
        }
        guard backup.physicalAssets.allSatisfy({ dto in
            let purchase = dto.purchasePrice.decimalValue
            let salvage = dto.salvageValue.decimalValue
            return purchase > 0 && salvage >= 0 && salvage <= purchase
                && dto.targetDailyCost.decimalValue > 0
                && (dto.soldPrice?.decimalValue ?? 0) >= 0
        }) else {
            throw ImportError.invalidContents("实物资产金额超出有效范围")
        }
        guard backup.recurringRules.allSatisfy({ $0.amount.decimalValue > 0 }),
              backup.budgets.allSatisfy({ $0.monthlyLimit.decimalValue > 0 }),
              backup.cashPoolItems.allSatisfy({ $0.amount.decimalValue >= 0 }),
              backup.installmentBills.allSatisfy({ $0.totalAmount.decimalValue > 0 }),
              backup.savingsGoals.allSatisfy({ $0.targetAmount.decimalValue > 0 && $0.currentAmount.decimalValue >= 0 }),
              backup.templates.allSatisfy({ $0.amount.decimalValue > 0 }) else {
            throw ImportError.invalidContents("存在不符合业务约束的金额")
        }

        if mode == .replace {
            let categoryIDs = Set(backup.categories.map { UUID(uuidString: $0.id)! })
            let ledgerIDs = Set(backup.ledgers.map { UUID(uuidString: $0.id)! })
            let recurringRuleIDs = Set(backup.recurringRules.map { UUID(uuidString: $0.id)! })
            let categoryReferences = (backup.transactions.compactMap(\.categoryId)
                + backup.recurringRules.compactMap(\.categoryId)
                + backup.categories.compactMap(\.mergedIntoCategoryId))
                .map { UUID(uuidString: $0)! }
            let ledgerReferences = (backup.transactions.compactMap(\.ledgerId)
                + backup.recurringRules.compactMap(\.ledgerId)
                + backup.budgets.compactMap(\.ledgerId))
                .map { UUID(uuidString: $0)! }
            let recurringRuleReferences = backup.transactions.compactMap(\.recurringRuleId)
                .map { UUID(uuidString: $0)! }
            let occurrenceRuleReferences = backup.recurringOccurrences.compactMap(\.ruleId)
                .map { UUID(uuidString: $0)! }
            let occurrenceTransactionReferences = backup.recurringOccurrences.compactMap(\.transactionId)
                .map { UUID(uuidString: $0)! }
            guard categoryReferences.allSatisfy(categoryIDs.contains) else {
                throw ImportError.invalidContents("分类关系引用不存在")
            }
            guard ledgerReferences.allSatisfy(ledgerIDs.contains) else {
                throw ImportError.invalidContents("账本关系引用不存在")
            }
            guard recurringRuleReferences.allSatisfy(recurringRuleIDs.contains) else {
                throw ImportError.invalidContents("周期规则关系引用不存在")
            }
            guard occurrenceRuleReferences.allSatisfy(recurringRuleIDs.contains) else {
                throw ImportError.invalidContents("周期发生项规则引用不存在")
            }
            let transactionIDs = Set(backup.transactions.map { UUID(uuidString: $0.id)! })
            guard occurrenceTransactionReferences.allSatisfy(transactionIDs.contains) else {
                throw ImportError.invalidContents("周期发生项交易引用不存在")
            }
        }
    }

    private static func validateUniqueIDs(_ ids: [String], label: String) throws {
        guard ids.allSatisfy({ UUID(uuidString: $0) != nil }) else {
            throw ImportError.invalidContents("\(label)包含无效 UUID")
        }
        guard Set(ids.compactMap(UUID.init(uuidString:))).count == ids.count else {
            throw ImportError.invalidContents("\(label)包含重复 UUID")
        }
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
        try deleteAll(Reminder.self); try deleteAll(RecurringOccurrence.self)
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        for item in try modelContext.fetch(FetchDescriptor<T>()) { modelContext.delete(item) }
    }

    @discardableResult
    private func restoreRemindersFromRecoveredImport(
        _ reminders: [ReminderItem],
        mode: ImportMode
    ) throws -> Int {
        do {
            let existing = try modelContext.fetch(FetchDescriptor<Reminder>())
            if mode == .replace {
                for reminder in existing {
                    modelContext.delete(reminder)
                }
            }

            let existingIDs = mode == .replace ? Set<UUID>() : Set(existing.map(\.id))
            var importedIDs = Set<UUID>()
            var importedCount = 0
            for reminder in reminders where
                !existingIDs.contains(reminder.id) && importedIDs.insert(reminder.id).inserted
            {
                modelContext.insert(Reminder(item: reminder))
                importedCount += 1
            }
            try modelContext.save()
            return importedCount
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func rebuildNotificationSchedule() {
        guard let reminders = try? ReminderDataService(modelContext: modelContext).load() else { return }
        Task { _ = try? await NotificationScheduleCoordinator.shared.rebuild(reminders: reminders) }
    }
}
