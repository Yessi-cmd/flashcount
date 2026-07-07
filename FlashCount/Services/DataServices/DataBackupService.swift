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
        let cashPoolItems: [CashPoolItemDTO]
        let cashPoolStates: [CashPoolStateDTO]
        let installmentBills: [InstallmentBillDTO]
        let savingsGoals: [SavingsGoalDTO]
        let templates: [TransactionTemplateDTO]
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
            self.settings = settings
        }

        enum CodingKeys: String, CodingKey {
            case version, createdAt, categories, ledgers, transactions, assets, physicalAssets, recurringRules, budgets
            case cashPoolItems, cashPoolStates, installmentBills, savingsGoals, templates, settings
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
        let amount: Double
        let isExpense: Bool
        let note: String
        let date: Date
        let createdAt: Date
        let categoryId: String?
        let ledgerId: String?
        let isPrivateIncome: Bool?
        let cashPoolDelta: Double?
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

    struct CashPoolItemDTO: Codable {
        let id: String
        let name: String
        let kind: String
        let amount: Double
        let note: String
        let isArchived: Bool
        let sortOrder: Int
        let createdAt: Date
        let updatedAt: Date
    }

    struct CashPoolStateDTO: Codable {
        let id: String
        let transactionDelta: Double
        let updatedAt: Date
    }

    struct InstallmentBillDTO: Codable {
        let id: String
        let name: String
        let totalAmount: Double
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
        let targetAmount: Double
        let currentAmount: Double
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
        let amount: Double
        let isExpense: Bool
        let note: String
        let categoryName: String?
        let sortOrder: Int
    }

    struct SettingsDTO: Codable {
        let payday: Int
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
        let cashPoolItems = (try? modelContext.fetch(FetchDescriptor<CashPoolItem>())) ?? []
        let cashPoolStates = (try? modelContext.fetch(FetchDescriptor<CashPoolState>())) ?? []
        let installmentBills = (try? modelContext.fetch(FetchDescriptor<InstallmentBill>())) ?? []
        let savingsGoals = (try? modelContext.fetch(FetchDescriptor<SavingsGoal>())) ?? []
        let templates = (try? modelContext.fetch(FetchDescriptor<TransactionTemplate>())) ?? []

        let backup = BackupData(
            version: "1.3.0",
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
                              ledgerId: t.ledger?.id.uuidString,
                              isPrivateIncome: t.isPrivateIncome,
                              cashPoolDelta: t.cashPoolDelta.map { NSDecimalNumber(decimal: $0).doubleValue })
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
            },
            cashPoolItems: cashPoolItems.map { item in
                CashPoolItemDTO(id: item.id.uuidString, name: item.name, kind: item.kind.rawValue,
                                amount: NSDecimalNumber(decimal: item.amount).doubleValue,
                                note: item.note, isArchived: item.isArchived,
                                sortOrder: item.sortOrder, createdAt: item.createdAt,
                                updatedAt: item.updatedAt)
            },
            cashPoolStates: cashPoolStates.map { state in
                CashPoolStateDTO(id: state.id.uuidString,
                                 transactionDelta: NSDecimalNumber(decimal: state.transactionDelta).doubleValue,
                                 updatedAt: state.updatedAt)
            },
            installmentBills: installmentBills.map { bill in
                InstallmentBillDTO(id: bill.id.uuidString, name: bill.name,
                                   totalAmount: NSDecimalNumber(decimal: bill.totalAmount).doubleValue,
                                   installmentCount: bill.installmentCount,
                                   paidInstallments: bill.paidInstallments,
                                   repaymentDay: bill.repaymentDay,
                                   firstRepaymentDate: bill.firstRepaymentDate,
                                   note: bill.note, isArchived: bill.isArchived,
                                   createdAt: bill.createdAt, updatedAt: bill.updatedAt)
            },
            savingsGoals: savingsGoals.map { goal in
                SavingsGoalDTO(id: goal.id.uuidString, name: goal.name,
                               targetAmount: NSDecimalNumber(decimal: goal.targetAmount).doubleValue,
                               currentAmount: NSDecimalNumber(decimal: goal.currentAmount).doubleValue,
                               targetDate: goal.targetDate, note: goal.note,
                               isCompleted: goal.isCompleted, isArchived: goal.isArchived,
                               createdAt: goal.createdAt, updatedAt: goal.updatedAt)
            },
            templates: templates.map { t in
                TransactionTemplateDTO(id: t.id.uuidString, name: t.name,
                                       amount: NSDecimalNumber(decimal: t.amount).doubleValue,
                                       isExpense: t.isExpense, note: t.note,
                                       categoryName: t.categoryName, sortOrder: t.sortOrder)
            },
            settings: SettingsDTO(payday: max(UserDefaults.standard.integer(forKey: "payday"), 1))
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

        let existingLedgers = (try? modelContext.fetch(FetchDescriptor<Ledger>())) ?? []
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
        let existingTransactions = (try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? []
        let existingTransIDs = Set(existingTransactions.map { $0.id.uuidString })

        // 找到默认账本，作为无归属交易的 fallback
        let defaultLedger = ledgerMap.values.first(where: { $0.isDefault }) ?? ledgerMap.values.first

        for dto in backup.transactions {
            if existingTransIDs.contains(dto.id) {
                result.skipped += 1
                continue
            }
            // 如果 ledgerId 匹配不到已有账本，则归入默认账本
            let matchedLedger = dto.ledgerId.flatMap { ledgerMap[$0] } ?? defaultLedger
            let t = Transaction(amount: Decimal(dto.amount), isExpense: dto.isExpense,
                               note: dto.note, date: dto.date,
                               isPrivateIncome: dto.isPrivateIncome ?? false,
                               cashPoolDelta: dto.cashPoolDelta.map { Decimal($0) },
                               category: dto.categoryId.flatMap { categoryMap[$0] },
                               ledger: matchedLedger)
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

        // 7. 导入资金池
        let existingCashItems = (try? modelContext.fetch(FetchDescriptor<CashPoolItem>())) ?? []
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
                amount: Decimal(dto.amount),
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

        let existingCashStates = (try? modelContext.fetch(FetchDescriptor<CashPoolState>())) ?? []
        let existingCashStateIDs = Set(existingCashStates.map { $0.id.uuidString })

        for dto in backup.cashPoolStates {
            if existingCashStateIDs.contains(dto.id) {
                result.skipped += 1; continue
            }
            let state = CashPoolState(transactionDelta: Decimal(dto.transactionDelta))
            if let id = UUID(uuidString: dto.id) { state.id = id }
            state.updatedAt = dto.updatedAt
            modelContext.insert(state)
        }

        // 8. 导入分期账单
        let existingInstallmentBills = (try? modelContext.fetch(FetchDescriptor<InstallmentBill>())) ?? []
        let existingInstallmentBillIDs = Set(existingInstallmentBills.map { $0.id.uuidString })

        for dto in backup.installmentBills {
            if existingInstallmentBillIDs.contains(dto.id) {
                result.skipped += 1; continue
            }
            let bill = InstallmentBill(
                name: dto.name,
                totalAmount: Decimal(dto.totalAmount),
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
        let existingSavingsGoals = (try? modelContext.fetch(FetchDescriptor<SavingsGoal>())) ?? []
        let existingSavingsGoalIDs = Set(existingSavingsGoals.map { $0.id.uuidString })

        for dto in backup.savingsGoals {
            if existingSavingsGoalIDs.contains(dto.id) {
                result.skipped += 1; continue
            }
            let goal = SavingsGoal(
                name: dto.name,
                targetAmount: Decimal(dto.targetAmount),
                currentAmount: Decimal(dto.currentAmount),
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
        let existingTemplates = (try? modelContext.fetch(FetchDescriptor<TransactionTemplate>())) ?? []
        let existingTemplateIDs = Set(existingTemplates.map { $0.id.uuidString })

        for dto in backup.templates {
            if existingTemplateIDs.contains(dto.id) {
                result.skipped += 1; continue
            }
            let template = TransactionTemplate(
                name: dto.name,
                amount: Decimal(dto.amount),
                isExpense: dto.isExpense,
                note: dto.note,
                categoryName: dto.categoryName,
                sortOrder: dto.sortOrder
            )
            if let id = UUID(uuidString: dto.id) { template.id = id }
            modelContext.insert(template)
            result.templatesImported += 1
        }

        if let settings = backup.settings {
            UserDefaults.standard.set(min(max(settings.payday, 1), 31), forKey: "payday")
        }

        try modelContext.save()
        return result
    }
}
