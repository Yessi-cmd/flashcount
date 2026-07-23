import Foundation
import SwiftData

/// Handles non-destructive startup data preparation.
@MainActor
final class DefaultDataService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Performs all launch-time data preparation. The caller owns error
    /// presentation so a failed recovery or migration never appears as a
    /// successful app launch.
    func prepareAppData(initialRecurringLimit: Int = 30) throws -> RecurringService.ProcessingResult {
        do {
            try stageDefaultData()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        _ = try DataBackupService(modelContext: modelContext).recoverPendingImport()

        _ = try ReminderDataService(modelContext: modelContext).migrateLegacyFileIfNeeded()

        let recurringService = RecurringService(modelContext: modelContext)
        return try recurringService.processDueRules(maxOccurrences: initialRecurringLimit)
    }

    /// 在当前 ModelContext 中准备默认数据，但不主动保存。
    /// 供备份恢复将删除、导入和单账本整理放进同一次数据库提交。
    func stageDefaultData() throws {
        try ensureDefaultLedgers()
        try ensureDefaultCategories()
        try ensureDefaultTemplates()
    }

    private func ensureDefaultLedgers() throws {
        let existing = try modelContext.fetch(FetchDescriptor<Ledger>())
        let existingNames = Set(existing.map(\.name))
        let appendMode = !existing.isEmpty
        var nextSortOrder = ((existing.map(\.sortOrder).max()) ?? -1) + 1

        for ledger in Ledger.defaultLedgers() where !existingNames.contains(ledger.name) {
            if appendMode {
                ledger.sortOrder = nextSortOrder
                nextSortOrder += 1
            }
            modelContext.insert(ledger)
        }

        let refreshed = try modelContext.fetch(FetchDescriptor<Ledger>())
        guard let primary = refreshed.first(where: { $0.name == "生活" }) ?? refreshed.first else { return }
        primary.isDefault = true
        primary.isArchived = false

        // The product is single-ledger. Preserve historical records by moving
        // transactions and recurring rules to the primary ledger. Budgets are
        // global in the single-ledger UI, so detach every budget before legacy
        // ledgers are deleted, including budgets already bound to the primary.
        let transactions = try modelContext.fetch(FetchDescriptor<Transaction>())
        for transaction in transactions where transaction.ledger?.id != primary.id {
            transaction.ledger = primary
        }

        let rules = try modelContext.fetch(FetchDescriptor<RecurringRule>())
        for rule in rules where rule.ledger?.id != primary.id {
            rule.ledger = primary
        }

        let budgets = try modelContext.fetch(FetchDescriptor<Budget>())
        for budget in budgets {
            budget.ledger = nil
        }

        for ledger in refreshed where ledger.id != primary.id {
            modelContext.delete(ledger)
        }
    }

    private func ensureDefaultCategories() throws {
        let existing = try modelContext.fetch(FetchDescriptor<Category>())
        freezeLegacyDailyBudgetScope(in: existing)
        ensureCategories(Category.defaultExpenseCategories(), isExpense: true, existing: existing)
        ensureCategories(Category.defaultIncomeCategories(), isExpense: false, existing: existing)
        try archiveLegacyExpenseCategories()
    }

    /// Freezes the name-based behavior from versions before categories had
    /// stable default keys. This is migration-only; runtime scope decisions use
    /// overrides and default keys, never mutable display names.
    private func freezeLegacyDailyBudgetScope(in categories: [Category]) {
        for category in categories where
            category.isExpense
            && category.defaultKey == nil
            && category.dailyBudgetOverride == nil
        {
            category.dailyBudgetOverride = BudgetScope.legacyIncludesCategory(named: category.name)
        }
    }

    private func ensureCategories(_ defaults: [Category], isExpense: Bool, existing: [Category]) {
        var existingKeys = Set(existing.map { "\($0.name)_\($0.isExpense)" })
        var existingDefaultKeys = Set(existing.compactMap(\.defaultKey))
        let appendMode = existing.contains { $0.isExpense == isExpense }
        var nextSortOrder = ((existing.filter { $0.isExpense == isExpense }.map(\.sortOrder).max()) ?? -1) + 1

        for category in defaults {
            if let defaultKey = category.defaultKey,
               let existingDefault = existing.first(where: { $0.defaultKey == defaultKey }) {
                if existingDefault.parentCategoryName == nil {
                    existingDefault.parentCategoryName = category.parentCategoryName
                }
                continue
            }

            let key = "\(category.name)_\(category.isExpense)"
            if let matchingName = existing.first(where: {
                $0.name == category.name && $0.isExpense == category.isExpense
            }) {
                matchingName.defaultKey = category.defaultKey
                if matchingName.parentCategoryName == nil {
                    matchingName.parentCategoryName = category.parentCategoryName
                }
                if let defaultKey = category.defaultKey { existingDefaultKeys.insert(defaultKey) }
                continue
            }
            guard !existingKeys.contains(key),
                  category.defaultKey.map({ !existingDefaultKeys.contains($0) }) ?? true else { continue }

            if appendMode {
                category.sortOrder = nextSortOrder
                nextSortOrder += 1
            }
            modelContext.insert(category)
            existingKeys.insert(key)
            if let defaultKey = category.defaultKey { existingDefaultKeys.insert(defaultKey) }
        }
    }

    private func archiveLegacyExpenseCategories() throws {
        let legacyNames = Category.archivedLegacyExpenseCategoryNames()
        let categories = try modelContext.fetch(FetchDescriptor<Category>())

        for category in categories where category.isExpense && legacyNames.contains(category.name) {
            category.isArchived = true
        }
    }

    private func ensureDefaultTemplates() throws {
        let existing = try modelContext.fetch(FetchDescriptor<TransactionTemplate>())
        guard existing.isEmpty else { return } // 只首次安装时写入
        for template in TransactionTemplate.defaultTemplates() {
            modelContext.insert(template)
        }
    }
}
