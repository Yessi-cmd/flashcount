import Foundation
import SwiftData

/// 资金池的读写。
///
/// 核心公式：可动用资金 = 资金净额 + 记账增减 − 分期待还。其中「记账增减」
/// 是自安装起累加的 `CashPoolState.transactionDelta`，用户无从自行核对，
/// 所以资产页要能下钻到它背后的交易。`state()` 顺带把历史导入可能留下的
/// 多条状态合并成一条——多条会让余额来源不确定。
/// `calibrate` 是最后手段：它把差异抹平，而不是解释差异。
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

    func state() throws -> CashPoolState {
        let descriptor = FetchDescriptor<CashPoolState>(
            sortBy: [SortDescriptor(\CashPoolState.updatedAt, order: .reverse)]
        )
        let states = try modelContext.fetch(descriptor)
        if let primary = states.first {
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

    func apply(delta: Decimal) throws {
        let currentState = try state()
        currentState.transactionDelta += delta
        currentState.updatedAt = Date()
    }

    func replace(oldDelta: Decimal?, newDelta: Decimal) throws {
        let currentState = try state()
        if let oldDelta {
            currentState.transactionDelta -= oldDelta
        }
        currentState.transactionDelta += newDelta
        currentState.updatedAt = Date()
    }

    func reverse(delta: Decimal?) throws {
        guard let delta else { return }
        let currentState = try state()
        currentState.transactionDelta -= delta
        currentState.updatedAt = Date()
    }

    func calibrate(to targetAmount: Decimal, items: [CashPoolItem], installmentLiability: Decimal = 0) throws {
        let currentState = try state()
        currentState.transactionDelta = targetAmount - manualTotal(items: items) + installmentLiability
        currentState.updatedAt = Date()
    }

    /// Applies deltas for newly imported transactions when merging a backup
    /// into an existing local data set. A complete restore imports the saved
    /// state instead, so this deliberately accepts an explicit aggregate.
    func applyImportedTransactionDeltas(_ delta: Decimal) throws {
        guard delta != 0 else { return }
        try apply(delta: delta)
    }
}
