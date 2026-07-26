import Foundation
import SwiftData

/// 储蓄目标的存入 / 取出。
///
/// 刻意不生成交易：钱只是从「可动用」挪到「已存」，并没有离开你。
/// 记成支出会污染预算与报表，把攒钱算成花钱。
@MainActor
struct SavingsGoalService {
    enum AdjustmentError: LocalizedError {
        case nonPositiveAmount
        case withdrawExceedsBalance(available: Decimal)

        var errorDescription: String? {
            switch self {
            case .nonPositiveAmount:
                return "金额必须大于零"
            case .withdrawExceedsBalance(let available):
                return "取出金额不能超过已存的 \(available.formattedCurrency)"
            }
        }
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func deposit(_ amount: Decimal, into goal: SavingsGoal) throws {
        guard amount > 0 else { throw AdjustmentError.nonPositiveAmount }
        try adjust(goal, by: amount)
    }

    func withdraw(_ amount: Decimal, from goal: SavingsGoal) throws {
        guard amount > 0 else { throw AdjustmentError.nonPositiveAmount }
        guard amount <= goal.currentAmount else {
            throw AdjustmentError.withdrawExceedsBalance(available: goal.currentAmount)
        }
        try adjust(goal, by: -amount)
    }

    /// 已存金额跨过目标线时同步完成状态——否则用户存满了还要自己去点一下「标记完成」。
    private func adjust(_ goal: SavingsGoal, by delta: Decimal) throws {
        let previousAmount = goal.currentAmount
        let previousCompleted = goal.isCompleted
        let previousUpdatedAt = goal.updatedAt

        goal.currentAmount = max(previousAmount + delta, 0)
        goal.isCompleted = goal.targetAmount > 0 && goal.currentAmount >= goal.targetAmount
        goal.updatedAt = Date()

        do {
            try modelContext.save()
        } catch {
            // rollback 之外再显式还原，确保内存里的目标不会停在半更新状态。
            modelContext.rollback()
            goal.currentAmount = previousAmount
            goal.isCompleted = previousCompleted
            goal.updatedAt = previousUpdatedAt
            throw error
        }
    }
}
