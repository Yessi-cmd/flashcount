import Foundation
import SwiftData

@Model
final class SavingsGoal {
    var id: UUID
    var name: String
    var targetAmount: Decimal
    var currentAmount: Decimal
    var targetDate: Date?
    var note: String
    var isCompleted: Bool
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    var remainingAmount: Decimal {
        max(targetAmount - currentAmount, 0)
    }

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(1, NSDecimalNumber(decimal: currentAmount / targetAmount).doubleValue)
    }

    init(
        name: String,
        targetAmount: Decimal,
        currentAmount: Decimal = 0,
        targetDate: Date? = nil,
        note: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.targetDate = targetDate
        self.note = note
        self.isCompleted = currentAmount >= targetAmount
        self.isArchived = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
