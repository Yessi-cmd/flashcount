import Foundation
import SwiftData

/// 账本（生活、生意、装修、旅行等）
@Model
final class Ledger {
    var id: UUID
    var name: String
    var icon: String          // SF Symbol name
    var colorHex: String
    var isDefault: Bool       // 默认账本标记
    var isArchived: Bool
    var createdAt: Date
    var sortOrder: Int

    @Relationship(deleteRule: .cascade, inverse: \Transaction.ledger)
    var transactions: [Transaction] = []

    @Relationship(deleteRule: .cascade, inverse: \Budget.ledger)
    var budgets: [Budget] = []

    @Relationship(deleteRule: .nullify, inverse: \RecurringRule.ledger)
    var recurringRules: [RecurringRule] = []

    init(
        name: String,
        icon: String,
        colorHex: String,
        isDefault: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.isDefault = isDefault
        self.isArchived = false
        self.createdAt = Date()
        self.sortOrder = sortOrder
    }

    // MARK: - 默认账本

    static func defaultLedgers() -> [Ledger] {
        [
            Ledger(name: "生活", icon: "house.fill", colorHex: "#667EEA", isDefault: true, sortOrder: 0),
            Ledger(name: "生意", icon: "briefcase.fill", colorHex: "#F093FB", sortOrder: 1),
        ]
    }
}
