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
        if let existing = try? modelContext.fetch(FetchDescriptor<CashPoolState>()).first {
            return existing
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
}
