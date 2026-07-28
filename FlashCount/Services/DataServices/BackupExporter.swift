import Foundation
import SwiftData

// MARK: - 导出

extension DataBackupService {
    func exportJSON() throws -> Data {
        let categories = try modelContext.fetch(FetchDescriptor<Category>())
        let ledgers = try modelContext.fetch(FetchDescriptor<Ledger>())
        let transactions = try modelContext.fetch(FetchDescriptor<Transaction>())
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
            assets: [], // 账户体系已移除；保留字段只为兼容旧版本读取
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
                CashPoolItemDTO(id: item.id.uuidString, name: item.name, kind: item.kind.backupKey,
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
}
