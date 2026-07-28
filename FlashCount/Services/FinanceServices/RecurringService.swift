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

    struct ProcessingResult: Equatable {
        let generatedCount: Int
        let hasRemainingDueRules: Bool
    }

    enum ProcessingError: LocalizedError {
        case invalidRuleAmount(UUID)

        var errorDescription: String? {
            switch self {
            case .invalidRuleAmount(let ruleID):
                return "周期规则 \(ruleID.uuidString) 的金额无效，未生成交易"
            }
        }
    }

    /// 处理一个有限批次的到期规则。每一笔交易、资金池变动和规则游标都
    /// 在同一次保存中提交；读取或保存失败会传递给调用方，绝不静默跳过。
    func processDueRules(
        maxOccurrences: Int = 30,
        now: Date = .now,
        mode: RecurringCatchUpMode = .automatic
    ) throws -> ProcessingResult {
        precondition(maxOccurrences > 0, "周期规则批次上限必须大于零")
        var generatedCount = 0
        var completed = false
        defer {
            if !completed {
                // Reconciliation and cursor changes are in-memory until the
                // transaction reaches a save boundary. Never leave them
                // behind when a later fetch or save fails.
                modelContext.rollback()
            }
        }

        // Existing transactions are registered before either automatic or
        // review-mode processing so a schema upgrade cannot create duplicates.
        try RecurringOccurrenceService(modelContext: modelContext).reconcileLegacyOccurrences()

        // Review mode leaves due rules untouched. The recurring-rules screen
        // presents the pure preview and resolves it in one atomic batch.
        guard mode == .automatic else {
            try saveChanges()
            completed = true
            return ProcessingResult(generatedCount: 0, hasRemainingDueRules: false)
        }

        // 获取所有活跃的周期规则
        let descriptor = FetchDescriptor<RecurringRule>(
            predicate: #Predicate<RecurringRule> { rule in
                rule.isActive == true
            }
        )

        let rules = try modelContext.fetch(descriptor)
        let existingOccurrences = try modelContext.fetch(FetchDescriptor<RecurringOccurrence>())
        var occurrencesByKey = Dictionary(uniqueKeysWithValues: existingOccurrences.map { ($0.occurrenceKey, $0) })

        let cashPoolService = CashPoolService(modelContext: modelContext)

        for rule in rules {
            guard MoneyValidation.positive(rule.amount) else {
                throw ProcessingError.invalidRuleAmount(rule.id)
            }
            if rule.anchorDay == nil,
               rule.frequency == .monthly || rule.frequency == .yearly {
                rule.anchorDay = Calendar.current.component(.day, from: rule.nextDueDate)
            }

            // 对每个规则，可能需要生成多笔交易（如果用户很久没打开 App）
            while rule.nextDueDate <= now, generatedCount < maxOccurrences {
                let dueDate = rule.nextDueDate
                if let endDate = rule.endDate, dueDate > endDate {
                    rule.isActive = false
                    break
                }
                let occurrenceKey = RecurringOccurrence.key(
                    ruleID: rule.id,
                    scheduledDate: dueDate
                )
                // A rule/date pair is the occurrence identity. This guards
                // against legacy interrupted runs that might already have
                // persisted the generated transaction.
                if let occurrence = occurrencesByKey[occurrenceKey], occurrence.status.isResolved {
                    guard let nextDate = rule.frequency.nextDate(from: dueDate, anchorDay: rule.anchorDay) else {
                        rule.isActive = false
                        break
                    }
                    rule.nextDueDate = nextDate
                    continue
                }

                if let existingTransaction = rule.generatedTransactions.first(where: { $0.date == dueDate }) {
                    let occurrence = RecurringOccurrence(
                        occurrenceKey: occurrenceKey,
                        ruleID: rule.id,
                        transactionID: existingTransaction.id,
                        scheduledDate: dueDate,
                        actualDate: existingTransaction.date,
                        amount: existingTransaction.amount,
                        isExpense: existingTransaction.isExpense,
                        title: rule.title,
                        note: existingTransaction.note,
                        categoryID: existingTransaction.category?.id,
                        ledgerID: existingTransaction.ledger?.id,
                        status: .generated,
                        resolvedAt: existingTransaction.createdAt
                    )
                    modelContext.insert(occurrence)
                    occurrencesByKey[occurrenceKey] = occurrence
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
                // save. A failed save is rolled back and surfaced to the caller
                // so a later launch cannot silently create a duplicate.
                do {
                    modelContext.insert(transaction)
                    let occurrence = RecurringOccurrence(
                        occurrenceKey: occurrenceKey,
                        ruleID: rule.id,
                        transactionID: transaction.id,
                        scheduledDate: dueDate,
                        actualDate: dueDate,
                        amount: transaction.amount,
                        isExpense: transaction.isExpense,
                        title: rule.title,
                        note: transaction.note,
                        categoryID: transaction.category?.id,
                        ledgerID: transaction.ledger?.id,
                        status: .generated,
                        resolvedAt: now
                    )
                    modelContext.insert(occurrence)
                    occurrencesByKey[occurrenceKey] = occurrence
                    try cashPoolService.apply(delta: cashDelta)
                    rule.nextDueDate = nextDate
                    try saveChanges()
                    generatedCount += 1
                } catch {
                    modelContext.rollback()
                    throw error
                }
            }

            if generatedCount == maxOccurrences { break }

            try saveChanges()
        }

        // This also persists legacy occurrence reconciliation when there were
        // no active rules or no due transactions to generate.
        try saveChanges()
        completed = true
        return ProcessingResult(
            generatedCount: generatedCount,
            hasRemainingDueRules: rules.contains { $0.isActive && $0.nextDueDate <= now }
        )
    }

    /// Backward-compatible convenience API for call sites that intentionally
    /// want one bounded startup-sized batch.
    @discardableResult
    func processAllDueRules() throws -> Int {
        try processDueRules(mode: .automatic).generatedCount
    }

    private func saveChanges() throws {
        guard modelContext.hasChanges else { return }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
