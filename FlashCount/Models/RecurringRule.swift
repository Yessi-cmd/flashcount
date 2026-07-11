import Foundation
import SwiftData

/// 周期频率
enum RecurringFrequency: String, Codable, CaseIterable {
    case daily = "每天"
    case weekly = "每周"
    case monthly = "每月"
    case yearly = "每年"

    /// 计算下一个到期日（nil = 已超出日历支持范围）。
    /// 月/年规则使用首次设置的日期作为锚点，短月份只临时夹到月末。
    func nextDate(
        from date: Date,
        anchorDay: Int? = nil,
        calendar: Calendar = .current
    ) -> Date? {
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly:
            return anchoredDate(
                byAdding: .month,
                to: date,
                anchorDay: anchorDay,
                calendar: calendar
            )
        case .yearly:
            return anchoredDate(
                byAdding: .year,
                to: date,
                anchorDay: anchorDay,
                calendar: calendar
            )
        }
    }

    private func anchoredDate(
        byAdding component: Calendar.Component,
        to date: Date,
        anchorDay: Int?,
        calendar: Calendar
    ) -> Date? {
        guard let target = calendar.date(byAdding: component, value: 1, to: date),
              let dayRange = calendar.range(of: .day, in: .month, for: target) else {
            return nil
        }

        let requestedDay = anchorDay ?? calendar.component(.day, from: date)
        var components = calendar.dateComponents(
            [.era, .year, .month, .hour, .minute, .second, .nanosecond],
            from: target
        )
        components.day = min(max(requestedDay, 1), dayRange.count)
        return calendar.date(from: components)
    }
}

extension RecurringRule {
    var isProtectedIncome: Bool {
        !isExpense && category?.isSalaryIncome == true
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
    /// 月/年规则的原始日期锚点。可选类型兼容已有 SwiftData 数据。
    var anchorDay: Int?
    var endDate: Date?
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
        endDate: Date? = nil,
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
        self.anchorDay = frequency == .monthly || frequency == .yearly
            ? Calendar.current.component(.day, from: nextDueDate)
            : nil
        self.endDate = endDate
        self.isActive = true
        self.note = note
        self.createdAt = Date()
        self.category = category
        self.ledger = ledger
    }
}
