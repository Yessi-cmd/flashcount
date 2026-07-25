import Foundation
import SwiftData

/// 已知周期规则在某个日期上的具体发生项。
///
/// 发生项本身不是账本交易；只有状态变为 generated 或 linked 后，才表示
/// 这次周期事件已经被真实账本处理。单独持久化发生项可以让补账幂等，
/// 也能在规则金额被修改后保留原始金额快照。
enum RecurringOccurrenceStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case generated
    case skipped
    case linked

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pending: return "待处理"
        case .generated: return "已补账"
        case .skipped: return "已跳过"
        case .linked: return "已关联"
        }
    }

    var isResolved: Bool {
        self == .generated || self == .skipped || self == .linked
    }
}

/// 周期规则的一个稳定发生项。`occurrenceKey` 是幂等边界，不能随交易编辑而改变。
@Model
final class RecurringOccurrence {
    var id: UUID
    var occurrenceKey: String
    var ruleID: UUID
    var transactionID: UUID?
    var scheduledDate: Date
    var actualDate: Date?
    var amount: Decimal
    var isExpense: Bool
    var title: String
    var note: String
    var categoryID: UUID?
    var ledgerID: UUID?
    var status: RecurringOccurrenceStatus
    var createdAt: Date
    var resolvedAt: Date?

    init(
        occurrenceKey: String,
        ruleID: UUID,
        transactionID: UUID? = nil,
        scheduledDate: Date,
        actualDate: Date? = nil,
        amount: Decimal,
        isExpense: Bool,
        title: String,
        note: String = "",
        categoryID: UUID? = nil,
        ledgerID: UUID? = nil,
        status: RecurringOccurrenceStatus = .pending,
        createdAt: Date = .now,
        resolvedAt: Date? = nil
    ) {
        self.id = UUID()
        self.occurrenceKey = occurrenceKey
        self.ruleID = ruleID
        self.transactionID = transactionID
        self.scheduledDate = scheduledDate
        self.actualDate = actualDate
        self.amount = amount
        self.isExpense = isExpense
        self.title = title
        self.note = note
        self.categoryID = categoryID
        self.ledgerID = ledgerID
        self.status = status
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }
}

extension RecurringOccurrence {
    var signedAmount: Decimal {
        isExpense ? -amount : amount
    }

    /// 当前产品的周期规则是日期级别的规则，因此发生项 key 不包含时分秒。
    static func key(
        ruleID: UUID,
        scheduledDate: Date,
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: scheduledDate)
        return "\(ruleID.uuidString)|\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}
