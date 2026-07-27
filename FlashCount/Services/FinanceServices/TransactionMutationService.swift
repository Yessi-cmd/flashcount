import Foundation
import SwiftData

/// Values collected by a transaction editor before they cross the persistence boundary.
struct TransactionDraft {
    let amount: Decimal
    let isExpense: Bool
    let note: String
    let date: Date
    let dailyBudgetOverride: Bool?
    let category: Category?
    let ledger: Ledger?

    init(
        amount: Decimal,
        isExpense: Bool,
        note: String = "",
        date: Date = Date(),
        dailyBudgetOverride: Bool? = nil,
        category: Category? = nil,
        ledger: Ledger? = nil
    ) {
        self.amount = amount
        self.isExpense = isExpense
        self.note = note
        self.date = date
        self.dailyBudgetOverride = dailyBudgetOverride
        self.category = category
        self.ledger = ledger
    }

    fileprivate func makeTransaction() -> Transaction {
        Transaction(
            amount: amount,
            isExpense: isExpense,
            note: note,
            date: date,
            isPrivateIncome: isPrivateIncome,
            dailyBudgetOverride: normalizedDailyBudgetOverride,
            category: category,
            ledger: ledger
        )
    }

    fileprivate func apply(to transaction: Transaction) {
        transaction.amount = amount
        transaction.isExpense = isExpense
        transaction.note = note
        transaction.date = date
        transaction.isPrivateIncome = isPrivateIncome
        transaction.dailyBudgetOverride = normalizedDailyBudgetOverride
        transaction.category = category
        transaction.ledger = ledger
    }

    private var isPrivateIncome: Bool {
        !isExpense && category?.isSalaryIncome == true
    }

    private var normalizedDailyBudgetOverride: Bool? {
        isExpense ? dailyBudgetOverride : nil
    }
}

/// Complete state needed to reverse a user-initiated deletion without changing identity.
struct DeletedTransactionSnapshot {
    fileprivate let id: UUID
    fileprivate let createdAt: Date
    fileprivate let amount: Decimal
    fileprivate let isExpense: Bool
    fileprivate let note: String
    fileprivate let date: Date
    fileprivate let isPrivateIncome: Bool
    fileprivate let cashPoolDelta: Decimal?
    fileprivate let dailyBudgetOverride: Bool?
    fileprivate let category: Category?
    fileprivate let ledger: Ledger?
    fileprivate let recurringRule: RecurringRule?

    fileprivate init(transaction: Transaction) {
        id = transaction.id
        createdAt = transaction.createdAt
        amount = transaction.amount
        isExpense = transaction.isExpense
        note = transaction.note
        date = transaction.date
        isPrivateIncome = transaction.isPrivateIncome
        cashPoolDelta = transaction.cashPoolDelta
        dailyBudgetOverride = transaction.dailyBudgetOverride
        category = transaction.category
        ledger = transaction.ledger
        recurringRule = transaction.recurringRule
    }

    fileprivate func makeTransaction() -> Transaction {
        let transaction = Transaction(
            amount: amount,
            isExpense: isExpense,
            note: note,
            date: date,
            isPrivateIncome: isPrivateIncome,
            cashPoolDelta: cashPoolDelta,
            dailyBudgetOverride: dailyBudgetOverride,
            category: category,
            ledger: ledger,
            recurringRule: recurringRule
        )
        transaction.id = id
        transaction.createdAt = createdAt
        return transaction
    }
}

/// 交易写入被拒绝的原因。金额一律正数存储，符号由 `isExpense` 决定，
/// 因此 0 与负数在这里就被挡住。
enum TransactionMutationError: LocalizedError {
    case invalidAmount

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "交易金额必须大于零"
        }
    }
}

/// Application boundary for user-driven transaction writes.
///
/// Every operation updates the transaction and its cash-pool projection before
/// issuing one save, so callers cannot persist only half of the financial state.
@MainActor
final class TransactionMutationService {
    private let modelContext: ModelContext
    private let cashPoolService: CashPoolService

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        cashPoolService = CashPoolService(modelContext: modelContext)
    }

    @discardableResult
    func create(_ draft: TransactionDraft) throws -> Transaction {
        try validate(draft)

        return try persistChanges {
            let transaction = draft.makeTransaction()
            let cashDelta = CashPoolService.transactionDelta(for: transaction)
            transaction.cashPoolDelta = cashDelta
            modelContext.insert(transaction)
            try cashPoolService.apply(delta: cashDelta)
            return transaction
        }
    }

    func update(_ transaction: Transaction, with draft: TransactionDraft) throws {
        try validate(draft)

        try persistChanges {
            let oldCashPoolDelta = transaction.cashPoolDelta
            draft.apply(to: transaction)
            let newCashPoolDelta = CashPoolService.transactionDelta(for: transaction)
            transaction.cashPoolDelta = newCashPoolDelta
            try cashPoolService.replace(oldDelta: oldCashPoolDelta, newDelta: newCashPoolDelta)
        }
    }

    @discardableResult
    func delete(_ transaction: Transaction) throws -> DeletedTransactionSnapshot {
        try persistChanges {
            let snapshot = DeletedTransactionSnapshot(transaction: transaction)
            try cashPoolService.reverse(delta: transaction.cashPoolDelta)
            modelContext.delete(transaction)
            return snapshot
        }
    }

    func delete(_ transactions: [Transaction]) throws {
        guard !transactions.isEmpty else { return }

        try persistChanges {
            var deletedIDs = Set<UUID>()
            for transaction in transactions where deletedIDs.insert(transaction.id).inserted {
                try cashPoolService.reverse(delta: transaction.cashPoolDelta)
                modelContext.delete(transaction)
            }
        }
    }

    @discardableResult
    func restore(_ snapshot: DeletedTransactionSnapshot) throws -> Transaction {
        try persistChanges {
            let transaction = snapshot.makeTransaction()
            modelContext.insert(transaction)
            if let cashPoolDelta = transaction.cashPoolDelta {
                try cashPoolService.apply(delta: cashPoolDelta)
            }
            return transaction
        }
    }

    private func validate(_ draft: TransactionDraft) throws {
        guard MoneyValidation.positive(draft.amount) else {
            throw TransactionMutationError.invalidAmount
        }
    }

    private func persistChanges<Result>(_ changes: () throws -> Result) throws -> Result {
        do {
            let result = try changes()
            try modelContext.save()
            return result
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
