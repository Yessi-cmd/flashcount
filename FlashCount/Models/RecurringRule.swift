import Foundation
import SwiftData

/// 周期频率
enum RecurringFrequency: String, Codable, CaseIterable {
    case daily = "每天"
    case weekly = "每周"
    case monthly = "每月"
    case yearly = "每年"

    /// 计算下一个到期日
    func nextDate(from date: Date) -> Date {
        let calendar = Calendar.current
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)!
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)!
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)!
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date)!
        }
    }
}

/// 周期性自动入账规则
@Model
final class RecurringRule {
    var id: UUID
    var title: String          // "房租" / "Netflix" / "iCloud"
    var amount: Decimal
    var isExpense: Bool
    var frequency: RecurringFrequency
    var nextDueDate: Date
    var isActive: Bool
    var note: String
    var createdAt: Date

    // 关系
    var category: Category?
    var ledger: Ledger?

    @Relationship(deleteRule: .nullify, inverse: \Transaction.recurringRule)
    var generatedTransactions: [Transaction] = []

    init(
        title: String,
        amount: Decimal,
        isExpense: Bool = true,
        frequency: RecurringFrequency = .monthly,
        nextDueDate: Date,
        note: String = "",
        category: Category? = nil,
        ledger: Ledger? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.amount = amount
        self.isExpense = isExpense
        self.frequency = frequency
        self.nextDueDate = nextDueDate
        self.isActive = true
        self.note = note
        self.createdAt = Date()
        self.category = category
        self.ledger = ledger
    }
}
