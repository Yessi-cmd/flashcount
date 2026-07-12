import Foundation
import SwiftData

/// 账本。当前 App 面向个人自用，默认只保留一个生活账本。
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
            Ledger(name: "生活", icon: "house.fill", colorHex: "#4E766A", isDefault: true, sortOrder: 0),
        ]
    }
}
