import Foundation
import SwiftData

/// 分期还款。
///
/// 「可动用资金 = 资金净额 + 交易增减 − 分期待还」。标记一期已还会让分期待还下降，
/// 若不同时把这笔钱记成支出，可动用资金就会凭空上涨——还了债反而显示更有钱。
/// 所以还款默认连带记账；只有用户已经手动记过这笔支出时才应跳过。
@MainActor
struct InstallmentRepaymentService {
    struct Draft {
        let amount: Decimal
        let date: Date
        let category: Category?
        /// 是否同时生成支出交易。已在账本手记过的用户可以关掉，避免重复计一笔。
        let recordsTransaction: Bool

        init(amount: Decimal, date: Date = Date(), category: Category? = nil, recordsTransaction: Bool = true) {
            self.amount = amount
            self.date = date
            self.category = category
            self.recordsTransaction = recordsTransaction
        }
    }

    enum RepaymentError: LocalizedError {
        case alreadyCompleted
        case invalidAmount
        case amountMismatch(expected: Decimal)

        var errorDescription: String? {
            switch self {
            case .alreadyCompleted: return "这笔分期已经还完了"
            case .invalidAmount: return "还款金额必须大于零"
            case .amountMismatch(let expected): return "本期还款金额必须为 \(expected.formattedCurrency)"
            }
        }
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// 默认还款金额：当期应还，最后一期会吸收除不尽的尾差。
    static func suggestedAmount(for bill: InstallmentBill) -> Decimal {
        bill.paymentAmount(forInstallment: bill.normalizedPaidInstallments)
    }

    /// 标记一期已还。期数推进与支出交易在同一次提交里完成，
    /// 任何一步失败都整体回滚，不会留下「记了账但期数没动」的中间态。
    @discardableResult
    func repayOneInstallment(_ bill: InstallmentBill, draft: Draft) throws -> Transaction? {
        guard !bill.isCompleted else { throw RepaymentError.alreadyCompleted }
        if draft.recordsTransaction {
            guard draft.amount > 0 else { throw RepaymentError.invalidAmount }
            let expectedAmount = Self.suggestedAmount(for: bill)
            guard draft.amount == expectedAmount else {
                throw RepaymentError.amountMismatch(expected: expectedAmount)
            }
        }

        let installmentIndex = bill.normalizedPaidInstallments

        do {
            bill.paidInstallments = min(installmentIndex + 1, bill.normalizedInstallmentCount)
            bill.updatedAt = Date()

            var created: Transaction?
            if draft.recordsTransaction {
                let transaction = Transaction(
                    amount: draft.amount,
                    isExpense: true,
                    note: "\(bill.name) 第 \(installmentIndex + 1) 期",
                    date: draft.date,
                    category: draft.category,
                    ledger: try defaultLedger()
                )
                let delta = CashPoolService.transactionDelta(for: transaction)
                transaction.cashPoolDelta = delta
                modelContext.insert(transaction)
                try CashPoolService(modelContext: modelContext).apply(delta: delta)
                created = transaction
            }

            try modelContext.save()
            return created
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func defaultLedger() throws -> Ledger? {
        let ledgers = try modelContext.fetch(FetchDescriptor<Ledger>(sortBy: [SortDescriptor(\Ledger.sortOrder)]))
        return ledgers.first(where: { $0.isDefault }) ?? ledgers.first
    }
}
