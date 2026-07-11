import Foundation
import SwiftData

@MainActor
final class CashPoolService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    static func transactionDelta(for transaction: Transaction) -> Decimal {
        transaction.isExpense ? -transaction.amount : transaction.amount
    }

    func availableAmount(items: [CashPoolItem], state: CashPoolState?, installmentLiability: Decimal = 0) -> Decimal {
        manualTotal(items: items) + (state?.transactionDelta ?? 0) - installmentLiability
    }

    func manualTotal(items: [CashPoolItem]) -> Decimal {
        items.filter { !$0.isArchived }.reduce(Decimal(0)) { $0 + $1.signedAmount }
    }

    func state() -> CashPoolState {
        let descriptor = FetchDescriptor<CashPoolState>(
            sortBy: [SortDescriptor(\CashPoolState.updatedAt, order: .reverse)]
        )
        if let states = try? modelContext.fetch(descriptor), let primary = states.first {
            // Historical imports could create more than one state. Consolidate
            // the duplicates into the newest record before any further mutation.
            for duplicate in states.dropFirst() {
                modelContext.delete(duplicate)
            }
            return primary
        }
        let state = CashPoolState()
        modelContext.insert(state)
        return state
    }

    func apply(delta: Decimal) {
        let currentState = state()
        currentState.transactionDelta += delta
        currentState.updatedAt = Date()
    }

    func replace(oldDelta: Decimal?, newDelta: Decimal) {
        let currentState = state()
        if let oldDelta {
            currentState.transactionDelta -= oldDelta
        }
        currentState.transactionDelta += newDelta
        currentState.updatedAt = Date()
    }

    func reverse(delta: Decimal?) {
        guard let delta else { return }
        let currentState = state()
        currentState.transactionDelta -= delta
        currentState.updatedAt = Date()
    }

    func calibrate(to targetAmount: Decimal, items: [CashPoolItem], installmentLiability: Decimal = 0) {
        let currentState = state()
        currentState.transactionDelta = targetAmount - manualTotal(items: items) + installmentLiability
        currentState.updatedAt = Date()
    }

    /// Applies deltas for newly imported transactions when merging a backup
    /// into an existing local data set. A complete restore imports the saved
    /// state instead, so this deliberately accepts an explicit aggregate.
    func applyImportedTransactionDeltas(_ delta: Decimal) {
        guard delta != 0 else { return }
        apply(delta: delta)
    }
}
