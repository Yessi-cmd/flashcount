import Foundation
import SwiftData

/// 交易记录
@Model
final class Transaction {
    var id: UUID
    var amount: Decimal       // 金额 (始终为正数)
    var isExpense: Bool       // true = 支出, false = 收入
    var note: String
    var date: Date
    var createdAt: Date
    var isPrivateIncome: Bool = false
    var cashPoolDelta: Decimal?

    // 关系
    var category: Category?
    var ledger: Ledger?
    var recurringRule: RecurringRule?  // 由周期规则自动生成时关联

    /// 签名金额：支出为负，收入为正
    var signedAmount: Decimal {
        isExpense ? -amount : amount
    }

    init(
        amount: Decimal,
        isExpense: Bool = true,
        note: String = "",
        date: Date = Date(),
        isPrivateIncome: Bool = false,
        cashPoolDelta: Decimal? = nil,
        category: Category? = nil,
        ledger: Ledger? = nil,
        recurringRule: RecurringRule? = nil
    ) {
        self.id = UUID()
        self.amount = amount
        self.isExpense = isExpense
        self.note = note
        self.date = date
        self.createdAt = Date()
        self.isPrivateIncome = isPrivateIncome
        self.cashPoolDelta = cashPoolDelta
        self.category = category
        self.ledger = ledger
        self.recurringRule = recurringRule
    }
}

extension Transaction {
    var isProtectedIncome: Bool {
        !isExpense && (isPrivateIncome || category?.isSalaryIncome == true)
    }
}
