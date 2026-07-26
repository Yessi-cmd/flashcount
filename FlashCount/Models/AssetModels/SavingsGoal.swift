import Foundation
import SwiftData

/// 一个储蓄目标。
///
/// 存入刻意不产生交易：钱从「可花」变成「存起来」，并没有离开。
/// 记一笔支出会让预算和报表把存钱算成花钱。也因此储蓄目标不计入净资产。
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
        return min(1, max(0, NSDecimalNumber(decimal: currentAmount / targetAmount).doubleValue))
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
        let normalizedCurrentAmount = max(currentAmount, 0)
        self.currentAmount = normalizedCurrentAmount
        self.targetDate = targetDate
        self.note = note
        self.isCompleted = normalizedCurrentAmount >= targetAmount
        self.isArchived = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
