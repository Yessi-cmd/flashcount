import Foundation
import SwiftData

/// Handles non-destructive startup data preparation.
@MainActor
final class DefaultDataService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func prepareAppData() {
        ensureDefaultLedgers()
        ensureDefaultCategories()
        ensureDefaultTemplates()
        try? modelContext.save()

        let recurringService = RecurringService(modelContext: modelContext)
        recurringService.processAllDueRules()
    }

    private func ensureDefaultLedgers() {
        let existing = (try? modelContext.fetch(FetchDescriptor<Ledger>())) ?? []
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

        let refreshed = (try? modelContext.fetch(FetchDescriptor<Ledger>())) ?? existing
        if !refreshed.contains(where: \.isDefault), let preferred = refreshed.first(where: { $0.name == "生活" }) ?? refreshed.first {
            preferred.isDefault = true
        }

        for ledger in refreshed where ledger.name == "生意" && ledger.transactions.isEmpty && ledger.budgets.isEmpty && ledger.recurringRules.isEmpty {
            modelContext.delete(ledger)
        }
    }

    private func ensureDefaultCategories() {
        let existing = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        ensureCategories(Category.defaultExpenseCategories(), isExpense: true, existing: existing)
        ensureCategories(Category.defaultIncomeCategories(), isExpense: false, existing: existing)
        archiveLegacyExpenseCategories()
    }

    private func ensureCategories(_ defaults: [Category], isExpense: Bool, existing: [Category]) {
        var existingKeys = Set(existing.map { "\($0.name)_\($0.isExpense)" })
        let appendMode = existing.contains { $0.isExpense == isExpense }
        var nextSortOrder = ((existing.filter { $0.isExpense == isExpense }.map(\.sortOrder).max()) ?? -1) + 1

        for category in defaults {
            let key = "\(category.name)_\(category.isExpense)"
            guard !existingKeys.contains(key) else { continue }

            if appendMode {
                category.sortOrder = nextSortOrder
                nextSortOrder += 1
            }
            modelContext.insert(category)
            existingKeys.insert(key)
        }
    }

    private func archiveLegacyExpenseCategories() {
        let legacyNames = Category.archivedLegacyExpenseCategoryNames()
        let categories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []

        for category in categories where category.isExpense && legacyNames.contains(category.name) {
            category.isArchived = true
        }
    }

    private func ensureDefaultTemplates() {
        let existing = (try? modelContext.fetch(FetchDescriptor<TransactionTemplate>())) ?? []
        guard existing.isEmpty else { return } // 只首次安装时写入
        for template in TransactionTemplate.defaultTemplates() {
            modelContext.insert(template)
        }
    }
}
