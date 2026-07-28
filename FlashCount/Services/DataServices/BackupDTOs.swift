import Foundation

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

// MARK: - 备份 DTO 定义

extension DataBackupService {
    enum ImportError: LocalizedError {
        case invalidVersion(String)
        case unsupportedVersion(String)
        case invalidContents(String)

        var errorDescription: String? {
            switch self {
            case .invalidVersion(let version):
                return "无法识别备份版本：\(version)"
            case .unsupportedVersion(let version):
                return "不支持备份版本 \(version)，当前支持 \(DataBackupService.minimumSupportedBackupVersion) 至 \(DataBackupService.currentBackupVersion)"
            case .invalidContents(let message):
                return "备份内容无效：\(message)"
            }
        }
    }

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

    struct ImportResult {
        var categoriesImported = 0
        var ledgersImported = 0
        var transactionsImported = 0
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
        var notificationWarning: String?

        var summary: String {
            var parts: [String] = []
            if categoriesImported > 0 { parts.append("分类 \(categoriesImported)") }
            if ledgersImported > 0 { parts.append("账本 \(ledgersImported)") }
            if transactionsImported > 0 { parts.append("账单 \(transactionsImported)") }
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
            let notificationStr = notificationWarning.map { "\n通知安排失败：\($0)" } ?? ""
            return importedStr + skippedStr + notificationStr
        }
    }
}
