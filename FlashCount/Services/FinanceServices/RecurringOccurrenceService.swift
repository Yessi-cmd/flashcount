import Foundation
import SwiftData

/// 一条待补记的周期发生项（还没写进账本）。
///
/// `id` 用 `occurrenceKey`（规则 + 计划日期）而不是 UUID，这样同一个到期日
/// 无论推演多少次都指向同一条，重复补账因此不会产生两笔。
struct RecurringOccurrencePreview: Identifiable, Equatable {
    let id: String
    let ruleID: UUID
    let scheduledDate: Date
    let amount: Decimal
    let isExpense: Bool
    let title: String
    let note: String
    let categoryID: UUID?
    let ledgerID: UUID?
    let isProtectedIncome: Bool

    var signedAmount: Decimal {
        isExpense ? -amount : amount
    }
}

/// 用户对一条待补记项的处置：生成一笔、跳过、或关联到已手工记过的交易。
/// `link` 存在的原因是用户常常已经自己记过了——再生成一笔就是重复记账。
enum RecurringBackfillAction: String, Codable {
    case generate
    case skip
    case link
}

/// 补账时对单条发生项的选择，可顺带改写金额与备注（实际扣款常与规则不同）。
struct RecurringBackfillSelection {
    let occurrenceKey: String
    let action: RecurringBackfillAction
    let transactionID: UUID?
    let amount: Decimal?
    let note: String?

    init(
        occurrenceKey: String,
        action: RecurringBackfillAction,
        transactionID: UUID? = nil,
        amount: Decimal? = nil,
        note: String? = nil
    ) {
        self.occurrenceKey = occurrenceKey
        self.action = action
        self.transactionID = transactionID
        self.amount = amount
        self.note = note
    }
}

/// 一次补账的结果。`cashPoolDelta` 汇报这批操作对现金的净影响，
/// 供调用方一次性对齐资金池，而不是每写一笔就改一次状态。
struct RecurringBackfillResult: Equatable {
    let generatedCount: Int
    let skippedCount: Int
    let linkedCount: Int
    let cashPoolDelta: Decimal
}

/// 负责周期发生项的预览、幂等处理与批量补账。
@MainActor
final class RecurringOccurrenceService {
    private let modelContext: ModelContext
    private let calendar: Calendar

    init(modelContext: ModelContext, calendar: Calendar = .current) {
        self.modelContext = modelContext
        self.calendar = calendar
    }

    /// 从当前规则游标生成待处理预览，不修改任何持久化数据。
    func pendingOccurrences(
        rules: [RecurringRule],
        occurrences: [RecurringOccurrence] = [],
        now: Date = .now,
        maxOccurrences: Int = 120
    ) -> [RecurringOccurrencePreview] {
        guard maxOccurrences > 0 else { return [] }

        let resolvedKeys = Set(occurrences.compactMap { occurrence in
            occurrence.status.isResolved ? occurrence.occurrenceKey : nil
        })
        var previews: [RecurringOccurrencePreview] = []

        for rule in rules where rule.isActive {
            guard previews.count < maxOccurrences else { break }
            var cursor = rule.nextDueDate
            var iterations = 0

            if rule.anchorDay == nil, rule.frequency == .monthly || rule.frequency == .yearly {
                // 仅用于纯计算，不在预览阶段改变规则。
            }

            while cursor <= now && iterations < maxOccurrences * 4 {
                iterations += 1
                if let endDate = rule.endDate, cursor > endDate {
                    break
                }

                let key = RecurringOccurrence.key(
                    ruleID: rule.id,
                    scheduledDate: cursor,
                    calendar: calendar
                )
                if !resolvedKeys.contains(key) {
                    previews.append(
                        RecurringOccurrencePreview(
                            id: key,
                            ruleID: rule.id,
                            scheduledDate: cursor,
                            amount: rule.amount,
                            isExpense: rule.isExpense,
                            title: rule.title,
                            note: rule.note,
                            categoryID: rule.category?.id,
                            ledgerID: rule.ledger?.id,
                            isProtectedIncome: rule.isProtectedIncome
                        )
                    )
                }

                guard let next = nextDate(for: rule, from: cursor) else { break }
                cursor = next
                if previews.count >= maxOccurrences { break }
            }
        }

        return previews.sorted {
            if $0.scheduledDate == $1.scheduledDate { return $0.title < $1.title }
            return $0.scheduledDate < $1.scheduledDate
        }
    }

    /// 将历史生成的周期交易登记为已处理发生项，避免新版本首次启动时重复补账。
    /// 不主动保存，由调用方把它放进自己的启动事务中。
    func reconcileLegacyOccurrences() throws {
        let transactions = try modelContext.fetch(FetchDescriptor<Transaction>())
        let existing = try modelContext.fetch(FetchDescriptor<RecurringOccurrence>())
        var existingKeys = Set(existing.map(\.occurrenceKey))

        for transaction in transactions {
            guard let rule = transaction.recurringRule else { continue }
            let key = RecurringOccurrence.key(
                ruleID: rule.id,
                scheduledDate: transaction.date,
                calendar: calendar
            )
            guard existingKeys.insert(key).inserted else { continue }

            modelContext.insert(
                RecurringOccurrence(
                    occurrenceKey: key,
                    ruleID: rule.id,
                    transactionID: transaction.id,
                    scheduledDate: transaction.date,
                    actualDate: transaction.date,
                    amount: transaction.amount,
                    isExpense: transaction.isExpense,
                    title: rule.title,
                    note: transaction.note,
                    categoryID: transaction.category?.id,
                    ledgerID: transaction.ledger?.id,
                    status: .generated,
                    resolvedAt: transaction.createdAt
                )
            )
        }
    }

    /// 批量确认补账。生成交易、资金池累计差额、发生项状态和规则游标
    /// 在一个 ModelContext 保存中完成。
    @discardableResult
    func resolve(
        _ selections: [RecurringBackfillSelection],
        now: Date = .now
    ) throws -> RecurringBackfillResult {
        guard !selections.isEmpty else {
            return RecurringBackfillResult(generatedCount: 0, skippedCount: 0, linkedCount: 0, cashPoolDelta: 0)
        }

        do {
            try reconcileLegacyOccurrences()
            let rules = try modelContext.fetch(FetchDescriptor<RecurringRule>())
            let occurrences = try modelContext.fetch(FetchDescriptor<RecurringOccurrence>())
            let transactions = try modelContext.fetch(FetchDescriptor<Transaction>())
            let categories = try modelContext.fetch(FetchDescriptor<Category>())
            let ledgers = try modelContext.fetch(FetchDescriptor<Ledger>())

            let ruleByID = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
            var occurrenceByKey = Dictionary(uniqueKeysWithValues: occurrences.map { ($0.occurrenceKey, $0) })
            let transactionByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
            let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
            let ledgerByID = Dictionary(uniqueKeysWithValues: ledgers.map { ($0.id, $0) })
            let availablePreviews = pendingOccurrences(
                rules: rules,
                occurrences: occurrences,
                now: now,
                maxOccurrences: max(selections.count * 2, 120)
            )
            let previewByKey = Dictionary(uniqueKeysWithValues: availablePreviews.map { ($0.id, $0) })

            var seenKeys = Set<String>()
            var cashPoolDelta: Decimal = 0
            var generatedCount = 0
            var skippedCount = 0
            var linkedCount = 0

            for selection in selections where seenKeys.insert(selection.occurrenceKey).inserted {
                guard let preview = previewByKey[selection.occurrenceKey],
                      let rule = ruleByID[preview.ruleID],
                      occurrenceByKey[selection.occurrenceKey] == nil else {
                    continue
                }

                switch selection.action {
                case .generate:
                    let amount = selection.amount ?? preview.amount
                    guard amount > 0 else { continue }
                    let category = preview.categoryID.flatMap { categoryByID[$0] } ?? rule.category
                    let ledger = preview.ledgerID.flatMap { ledgerByID[$0] } ?? rule.ledger
                    let selectedNote = selection.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let note = selectedNote.isEmpty
                        ? "[补账] \(preview.title)"
                        : selectedNote
                    let transaction = Transaction(
                        amount: amount,
                        isExpense: preview.isExpense,
                        note: note,
                        date: preview.scheduledDate,
                        isPrivateIncome: !preview.isExpense && category?.isSalaryIncome == true,
                        category: category,
                        ledger: ledger,
                        recurringRule: rule
                    )
                    let delta = CashPoolService.transactionDelta(for: transaction)
                    transaction.cashPoolDelta = delta
                    modelContext.insert(transaction)

                    let occurrence = RecurringOccurrence(
                        occurrenceKey: preview.id,
                        ruleID: rule.id,
                        transactionID: transaction.id,
                        scheduledDate: preview.scheduledDate,
                        actualDate: transaction.date,
                        amount: amount,
                        isExpense: preview.isExpense,
                        title: preview.title,
                        note: note,
                        categoryID: category?.id,
                        ledgerID: ledger?.id,
                        status: .generated,
                        resolvedAt: now
                    )
                    modelContext.insert(occurrence)
                    occurrenceByKey[preview.id] = occurrence
                    cashPoolDelta += delta
                    generatedCount += 1

                case .skip:
                    let occurrence = RecurringOccurrence(
                        occurrenceKey: preview.id,
                        ruleID: rule.id,
                        scheduledDate: preview.scheduledDate,
                        amount: preview.amount,
                        isExpense: preview.isExpense,
                        title: preview.title,
                        note: preview.note,
                        categoryID: preview.categoryID,
                        ledgerID: preview.ledgerID,
                        status: .skipped,
                        resolvedAt: now
                    )
                    modelContext.insert(occurrence)
                    occurrenceByKey[preview.id] = occurrence
                    skippedCount += 1

                case .link:
                    guard let transactionID = selection.transactionID,
                          transactionByID[transactionID] != nil else { continue }
                    let occurrence = RecurringOccurrence(
                        occurrenceKey: preview.id,
                        ruleID: rule.id,
                        transactionID: transactionID,
                        scheduledDate: preview.scheduledDate,
                        actualDate: transactionByID[transactionID]?.date,
                        amount: transactionByID[transactionID]?.amount ?? preview.amount,
                        isExpense: transactionByID[transactionID]?.isExpense ?? preview.isExpense,
                        title: preview.title,
                        note: transactionByID[transactionID]?.note ?? preview.note,
                        categoryID: transactionByID[transactionID]?.category?.id ?? preview.categoryID,
                        ledgerID: transactionByID[transactionID]?.ledger?.id ?? preview.ledgerID,
                        status: .linked,
                        resolvedAt: now
                    )
                    modelContext.insert(occurrence)
                    occurrenceByKey[preview.id] = occurrence
                    linkedCount += 1
                }
            }

            if cashPoolDelta != 0 {
                try CashPoolService(modelContext: modelContext).apply(delta: cashPoolDelta)
            }

            for rule in rules {
                advanceCursor(for: rule, occurrencesByKey: occurrenceByKey, now: now)
            }

            try modelContext.save()
            return RecurringBackfillResult(
                generatedCount: generatedCount,
                skippedCount: skippedCount,
                linkedCount: linkedCount,
                cashPoolDelta: cashPoolDelta
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func advanceCursor(
        for rule: RecurringRule,
        occurrencesByKey: [String: RecurringOccurrence],
        now: Date
    ) {
        var iterations = 0
        while rule.nextDueDate <= now && iterations < 2_000 {
            iterations += 1
            if let endDate = rule.endDate, rule.nextDueDate > endDate {
                rule.isActive = false
                break
            }
            let key = RecurringOccurrence.key(
                ruleID: rule.id,
                scheduledDate: rule.nextDueDate,
                calendar: calendar
            )
            guard occurrencesByKey[key]?.status.isResolved == true else { break }
            guard let next = nextDate(for: rule, from: rule.nextDueDate) else {
                rule.isActive = false
                break
            }
            rule.nextDueDate = next
        }
    }

    private func nextDate(for rule: RecurringRule, from date: Date) -> Date? {
        let anchorDay = rule.anchorDay ?? (
            rule.frequency == .monthly || rule.frequency == .yearly
                ? calendar.component(.day, from: date)
                : nil
        )
        return rule.frequency.nextDate(from: date, anchorDay: anchorDay, calendar: calendar)
    }
}
