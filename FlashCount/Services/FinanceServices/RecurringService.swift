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

        let rules: [RecurringRule]
        do {
            rules = try modelContext.fetch(descriptor)
        } catch {
            print("读取周期规则失败: \(error.localizedDescription)")
            return 0
        }

        let cashPoolService = CashPoolService(modelContext: modelContext)

        for rule in rules {
            if rule.anchorDay == nil, rule.frequency == .monthly || rule.frequency == .yearly {
                rule.anchorDay = Calendar.current.component(.day, from: rule.nextDueDate)
            }

            // 对每个规则，可能需要生成多笔交易（如果用户很久没打开 App）
            while rule.nextDueDate <= now {
                let dueDate = rule.nextDueDate
                if let endDate = rule.endDate, dueDate > endDate {
                    rule.isActive = false
                    break
                }
                // A rule/date pair is the occurrence identity. This guards
                // against legacy interrupted runs that might already have
                // persisted the generated transaction.
                if rule.generatedTransactions.contains(where: { $0.date == dueDate }) {
                    guard let nextDate = rule.frequency.nextDate(from: dueDate, anchorDay: rule.anchorDay) else {
                        rule.isActive = false
                        break
                    }
                    rule.nextDueDate = nextDate
                    continue
                }

                let transaction = Transaction(
                    amount: rule.amount,
                    isExpense: rule.isExpense,
                    note: "[\(rule.frequency.rawValue)] \(rule.title)",
                    date: dueDate,
                    isPrivateIncome: !rule.isExpense && rule.category?.isSalaryIncome == true,
                    category: rule.category,
                    ledger: rule.ledger,
                    recurringRule: rule
                )
                let cashDelta = CashPoolService.transactionDelta(for: transaction)
                transaction.cashPoolDelta = cashDelta
                guard let nextDate = rule.frequency.nextDate(from: dueDate, anchorDay: rule.anchorDay) else {
                    // 日历溢出，停用该规则避免死循环
                    rule.isActive = false
                    break
                }

                // Persist the occurrence, cash-pool change, and cursor in one
                // save. A failed save is rolled back so a later launch cannot
                // create a duplicate occurrence.
                modelContext.insert(transaction)
                cashPoolService.apply(delta: cashDelta)
                rule.nextDueDate = nextDate
                do {
                    try modelContext.save()
                    generatedCount += 1
                } catch {
                    modelContext.rollback()
                    break
                }
            }

            if modelContext.hasChanges {
                do {
                    try modelContext.save()
                } catch {
                    modelContext.rollback()
                    continue
                }
            }
        }

        return generatedCount
    }
}
