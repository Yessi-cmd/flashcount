import Foundation

/// The badge and the Action Center must invalidate from the same value inputs.
/// Counting model objects is not enough: editing an amount, due date, status, or
/// category can change the resulting sections without changing any collection
/// count.
enum LocalActionCenterDigest {
    static func make(
        budgets: [Budget],
        transactions: [Transaction],
        categories: [Category],
        recurringRules: [RecurringRule],
        occurrences: [RecurringOccurrence],
        installmentBills: [InstallmentBill],
        reminders: [Reminder],
        cashPoolItems: [CashPoolItem],
        cashPoolStates: [CashPoolState],
        payday: Int,
        weekendBudgetMultiplierPercent: Int,
        dismissedSuggestionFingerprints: Set<String>
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(payday)
        hasher.combine(weekendBudgetMultiplierPercent)

        for budget in budgets.sorted(by: sortByID) {
            hasher.combine(budget.id)
            hasher.combine(budget.monthlyLimit)
            hasher.combine(budget.year)
            hasher.combine(budget.month)
            hasher.combine(budget.createdAt)
            hasher.combine(budget.ledger?.id)
            hasher.combine(budget.categoryId)
        }

        for transaction in transactions.sorted(by: sortByID) {
            hasher.combine(transaction.id)
            hasher.combine(transaction.amount)
            hasher.combine(transaction.isExpense)
            hasher.combine(transaction.note)
            hasher.combine(transaction.date)
            hasher.combine(transaction.dailyBudgetOverride)
            hasher.combine(transaction.recurringRule?.id)
            hasher.combine(transaction.category?.id)
            hasher.combine(transaction.category?.name)
            hasher.combine(transaction.category?.isArchived)
            hasher.combine(transaction.category?.defaultKey)
            hasher.combine(transaction.category?.dailyBudgetOverride)
            hasher.combine(transaction.ledger?.id)
        }

        for category in categories.sorted(by: sortByID) {
            hasher.combine(category.id)
            hasher.combine(category.name)
            hasher.combine(category.isExpense)
            hasher.combine(category.isArchived)
            hasher.combine(category.dailyBudgetOverride)
            hasher.combine(category.defaultKey)
        }

        for rule in recurringRules.sorted(by: sortByID) {
            hasher.combine(rule.id)
            hasher.combine(rule.title)
            hasher.combine(rule.amount)
            hasher.combine(rule.isExpense)
            hasher.combine(rule.frequency.rawValue)
            hasher.combine(rule.nextDueDate)
            hasher.combine(rule.anchorDay)
            hasher.combine(rule.endDate)
            hasher.combine(rule.isActive)
            hasher.combine(rule.note)
            hasher.combine(rule.category?.id)
            hasher.combine(rule.ledger?.id)
        }

        for occurrence in occurrences.sorted(by: sortByID) {
            hasher.combine(occurrence.id)
            hasher.combine(occurrence.occurrenceKey)
            hasher.combine(occurrence.ruleID)
            hasher.combine(occurrence.transactionID)
            hasher.combine(occurrence.scheduledDate)
            hasher.combine(occurrence.actualDate)
            hasher.combine(occurrence.amount)
            hasher.combine(occurrence.isExpense)
            hasher.combine(occurrence.status.rawValue)
            hasher.combine(occurrence.resolvedAt)
        }

        for bill in installmentBills.sorted(by: sortByID) {
            hasher.combine(bill.id)
            hasher.combine(bill.name)
            hasher.combine(bill.totalAmount)
            hasher.combine(bill.installmentCount)
            hasher.combine(bill.paidInstallments)
            hasher.combine(bill.repaymentDay)
            hasher.combine(bill.firstRepaymentDate)
            hasher.combine(bill.isArchived)
        }

        for reminder in reminders.sorted(by: sortByID) {
            hasher.combine(reminder.id)
            hasher.combine(reminder.title)
            hasher.combine(reminder.note)
            hasher.combine(reminder.dueDate)
            hasher.combine(reminder.intensityRawValue)
            hasher.combine(reminder.isCompleted)
            hasher.combine(reminder.completedAt)
        }

        for item in cashPoolItems.sorted(by: sortByID) {
            hasher.combine(item.id)
            hasher.combine(item.name)
            hasher.combine(item.kind.rawValue)
            hasher.combine(item.amount)
            hasher.combine(item.isArchived)
            hasher.combine(item.sortOrder)
            hasher.combine(item.updatedAt)
        }

        for state in cashPoolStates.sorted(by: sortByID) {
            hasher.combine(state.id)
            hasher.combine(state.transactionDelta)
            hasher.combine(state.updatedAt)
        }

        for fingerprint in dismissedSuggestionFingerprints.sorted() {
            hasher.combine(fingerprint)
        }
        return hasher.finalize()
    }

    private static func sortByID(_ lhs: Budget, _ rhs: Budget) -> Bool { lhs.id.uuidString < rhs.id.uuidString }
    private static func sortByID(_ lhs: Transaction, _ rhs: Transaction) -> Bool { lhs.id.uuidString < rhs.id.uuidString }
    private static func sortByID(_ lhs: Category, _ rhs: Category) -> Bool { lhs.id.uuidString < rhs.id.uuidString }
    private static func sortByID(_ lhs: RecurringRule, _ rhs: RecurringRule) -> Bool { lhs.id.uuidString < rhs.id.uuidString }
    private static func sortByID(_ lhs: RecurringOccurrence, _ rhs: RecurringOccurrence) -> Bool { lhs.id.uuidString < rhs.id.uuidString }
    private static func sortByID(_ lhs: InstallmentBill, _ rhs: InstallmentBill) -> Bool { lhs.id.uuidString < rhs.id.uuidString }
    private static func sortByID(_ lhs: Reminder, _ rhs: Reminder) -> Bool { lhs.id.uuidString < rhs.id.uuidString }
    private static func sortByID(_ lhs: CashPoolItem, _ rhs: CashPoolItem) -> Bool { lhs.id.uuidString < rhs.id.uuidString }
    private static func sortByID(_ lhs: CashPoolState, _ rhs: CashPoolState) -> Bool { lhs.id.uuidString < rhs.id.uuidString }
}
