import Foundation
import SwiftData

// MARK: - 导入与中断恢复

extension DataBackupService {
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

        // 3. 旧备份里的「账户」在第 7 步随资金项一起折算导入（账户体系已移除）。

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
        var existingCashItemIDs = Set(existingCashItems.map(\.id))
        var nextCashItemSortOrder = (existingCashItems.map(\.sortOrder).max() ?? -1) + 1

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
            existingCashItemIDs.insert(dtoID)
            nextCashItemSortOrder = max(nextCashItemSortOrder, dto.sortOrder + 1)
            result.cashPoolItemsImported += 1
        }

        // 旧版备份里的「账户」折算成资金项，与数据库迁移走同一套规则。
        // 沿用账户原 UUID，这样同一份旧备份重复合并导入不会产生重复条目。
        for dto in backup.assets {
            let dtoID = UUID(uuidString: dto.id)!
            if existingCashItemIDs.contains(dtoID) {
                result.skipped += 1; continue
            }
            let item = LegacyAssetConversion.makeCashPoolItem(
                name: dto.name,
                rawType: dto.type,
                balance: dto.balance.decimalValue,
                existingNote: dto.note,
                isArchived: dto.isArchived,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt,
                sortOrder: nextCashItemSortOrder
            )
            item.id = dtoID
            modelContext.insert(item)
            existingCashItemIDs.insert(dtoID)
            nextCashItemSortOrder += 1
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

    private func deleteAllPersistedModels() throws {
        try deleteAll(Transaction.self); try deleteAll(Category.self); try deleteAll(Ledger.self)
        try deleteAll(RecurringRule.self); try deleteAll(Budget.self)
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
