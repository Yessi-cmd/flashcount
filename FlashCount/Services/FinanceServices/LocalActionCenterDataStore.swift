import Foundation
import SwiftData

/// Reads and aggregates the Action Center badge entirely on a model actor.
///
/// The ledger view receives one `Int`; it never replays recurring rules or
/// scans the full expense history on the main actor.
@ModelActor
actor LocalActionCenterDataStore {
    func totalCount(
        dismissedSuggestionFingerprints: Set<String>,
        payday: Int,
        weekendMultiplier: Decimal,
        referenceDate: Date = .now
    ) throws -> Int {
        let budgets = try modelContext.fetch(FetchDescriptor<Budget>())
        let transactions = try modelContext.fetch(
            FetchDescriptor<Transaction>(
                predicate: #Predicate<Transaction> { $0.isExpense == true },
                sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
            )
        )
        let recurringRules = try modelContext.fetch(
            FetchDescriptor<RecurringRule>(
                sortBy: [SortDescriptor(\RecurringRule.nextDueDate)]
            )
        )
        let occurrences = try modelContext.fetch(FetchDescriptor<RecurringOccurrence>())
        let installmentBills = try modelContext.fetch(FetchDescriptor<InstallmentBill>())
        let reminders = try modelContext.fetch(FetchDescriptor<Reminder>())
        let cashPoolItems = try modelContext.fetch(FetchDescriptor<CashPoolItem>())
        let cashPoolStates = try modelContext.fetch(
            FetchDescriptor<CashPoolState>(
                sortBy: [SortDescriptor(\CashPoolState.updatedAt, order: .reverse)]
            )
        )
        let pendingBackfill = RecurringOccurrencePreviewCalculator.pendingOccurrences(
            rules: recurringRules,
            occurrences: occurrences,
            now: referenceDate,
            maxOccurrences: 120
        )

        return LocalActionCenterService.snapshot(
            budgets: budgets,
            transactions: transactions,
            recurringRules: recurringRules,
            occurrences: occurrences,
            pendingBackfill: pendingBackfill,
            installmentBills: installmentBills,
            reminders: reminders.map(\.item),
            cashPoolItems: cashPoolItems,
            cashPoolState: cashPoolStates.first,
            dismissedSuggestionFingerprints: dismissedSuggestionFingerprints,
            referenceDate: referenceDate,
            payday: payday,
            weekendMultiplier: weekendMultiplier
        ).totalCount
    }
}
