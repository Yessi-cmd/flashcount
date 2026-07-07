import Foundation
import SwiftData

/// 周期性自动入账服务
/// App 启动时检查所有活跃规则，自动生成到期交易
@MainActor
final class RecurringService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// 处理所有到期的周期规则，生成交易
    /// - Returns: 本次生成的交易数量
    @discardableResult
    func processAllDueRules() -> Int {
        let now = Date()
        var generatedCount = 0

        // 获取所有活跃的周期规则
        let descriptor = FetchDescriptor<RecurringRule>(
            predicate: #Predicate<RecurringRule> { rule in
                rule.isActive == true
            }
        )

        guard let rules = try? modelContext.fetch(descriptor) else { return 0 }

        let cashPoolService = CashPoolService(modelContext: modelContext)

        for rule in rules {
            // 对每个规则，可能需要生成多笔交易（如果用户很久没打开 App）
            while rule.nextDueDate <= now {
                let transaction = Transaction(
                    amount: rule.amount,
                    isExpense: rule.isExpense,
                    note: "[\(rule.frequency.rawValue)] \(rule.title)",
                    date: rule.nextDueDate,
                    isPrivateIncome: !rule.isExpense && rule.category?.isSalaryIncome == true,
                    category: rule.category,
                    ledger: rule.ledger,
                    recurringRule: rule
                )
                let cashDelta = CashPoolService.transactionDelta(for: transaction)
                transaction.cashPoolDelta = cashDelta
                modelContext.insert(transaction)
                cashPoolService.apply(delta: cashDelta)

                // 推进到下一个周期
                rule.nextDueDate = rule.frequency.nextDate(from: rule.nextDueDate)
                generatedCount += 1
            }

            // 每条规则处理完后立即保存，避免单次保存失败导致所有规则的 nextDueDate 丢失
            if modelContext.hasChanges {
                do {
                    try modelContext.save()
                } catch {
                    // 保存失败时，该规则的内存变更会在下次启动时重置，允许重试
                    continue
                }
            }
        }

        return generatedCount
    }
}
