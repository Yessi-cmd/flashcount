import Foundation
import SwiftData

enum DataHealthError: LocalizedError, Equatable {
    case stalePreview

    var errorDescription: String? {
        switch self {
        case .stalePreview:
            return "本地数据在预览后发生了变化，请重新扫描。"
        }
    }
}

@MainActor
final class DataHealthService {
    private let modelContext: ModelContext

    struct RawReferenceKey: Hashable {
        let recordType: DataHealthRecordType
        let id: UUID
    }

    private struct DuplicateScanResult {
        let count: Int
        let repairableCount: Int
        let manualCount: Int
        let actions: [DataHealthRekeyAction]
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func scan() throws -> DataHealthReport {
        let transactions = try modelContext.fetch(FetchDescriptor<Transaction>())
        let categories = try modelContext.fetch(FetchDescriptor<Category>())
        let ledgers = try modelContext.fetch(FetchDescriptor<Ledger>())
        let recurringRules = try modelContext.fetch(FetchDescriptor<RecurringRule>())
        let recurringOccurrences = try modelContext.fetch(FetchDescriptor<RecurringOccurrence>())
        let budgets = try modelContext.fetch(FetchDescriptor<Budget>())
        let physicalAssets = try modelContext.fetch(FetchDescriptor<PhysicalAsset>())
        let cashPoolItems = try modelContext.fetch(FetchDescriptor<CashPoolItem>())
        let cashPoolStates = try modelContext.fetch(FetchDescriptor<CashPoolState>())
        let savingsGoals = try modelContext.fetch(FetchDescriptor<SavingsGoal>())
        let installmentBills = try modelContext.fetch(FetchDescriptor<InstallmentBill>())
        let transactionTemplates = try modelContext.fetch(FetchDescriptor<TransactionTemplate>())
        let reminders = try modelContext.fetch(FetchDescriptor<Reminder>())

        let fingerprint = makeFingerprint(
            transactions: transactions,
            categories: categories,
            ledgers: ledgers,
            recurringRules: recurringRules,
            recurringOccurrences: recurringOccurrences,
            budgets: budgets,
            physicalAssets: physicalAssets,
            cashPoolItems: cashPoolItems,
            cashPoolStates: cashPoolStates,
            savingsGoals: savingsGoals,
            installmentBills: installmentBills,
            transactionTemplates: transactionTemplates,
            reminders: reminders
        )

        let incomingReferences = rawReferences(
            categories: categories,
            recurringOccurrences: recurringOccurrences,
            budgets: budgets
        )

        var rekeyActions: [DataHealthRekeyAction] = []
        var duplicateUUIDCount = 0
        var duplicateUUIDRepairableCount = 0
        var duplicateUUIDManualCount = 0

        let duplicateCollections: [(DataHealthRecordType, [any DataHealthIdentifiedModel])] = [
            (.transaction, transactions),
            (.category, categories),
            (.ledger, ledgers),
            (.recurringRule, recurringRules),
            (.recurringOccurrence, recurringOccurrences),
            (.budget, budgets),
            (.physicalAsset, physicalAssets),
            (.cashPoolItem, cashPoolItems),
            (.savingsGoal, savingsGoals),
            (.installmentBill, installmentBills),
            (.transactionTemplate, transactionTemplates),
            (.reminder, reminders)
        ]

        for (recordType, objects) in duplicateCollections {
            let result = duplicateUUIDResult(
                objects: objects,
                recordType: recordType,
                incomingReferences: incomingReferences
            )
            duplicateUUIDCount += result.count
            duplicateUUIDRepairableCount += result.repairableCount
            duplicateUUIDManualCount += result.manualCount
            rekeyActions.append(contentsOf: result.actions)
        }

        let orphanBudgets = budgets.filter { budget in
            guard let categoryID = budget.categoryId else { return false }
            return !categories.contains { $0.id == categoryID }
        }

        let missingLedgerTransactions = transactions.filter { $0.ledger == nil }
        let defaultLedger = ledgers.first(where: { $0.isDefault }) ?? ledgers.first
        let ledgerForRepair: Ledger?
        let defaultLedgerToInsert: Ledger?
        if let defaultLedger {
            ledgerForRepair = defaultLedger
            defaultLedgerToInsert = nil
        } else if !missingLedgerTransactions.isEmpty {
            let createdLedger = Ledger.defaultLedgers()[0]
            ledgerForRepair = createdLedger
            defaultLedgerToInsert = createdLedger
        } else {
            ledgerForRepair = nil
            defaultLedgerToInsert = nil
        }

        let ledgerActions = missingLedgerTransactions.compactMap { transaction -> DataHealthLedgerAction? in
            guard let ledgerForRepair else { return nil }
            return DataHealthLedgerAction(transaction: transaction, ledger: ledgerForRepair)
        }

        let invalidAmountTransactions = transactions.filter { $0.amount <= 0 }
        let uncategorizedTransactions = transactions.filter { $0.category == nil }
        let emptyDeltaTransactions = transactions.filter { $0.cashPoolDelta == nil }
        let validEmptyDeltaTransactions = emptyDeltaTransactions.filter { $0.amount > 0 }
        let deltaValues = validEmptyDeltaTransactions.map {
            ($0, CashPoolService.transactionDelta(for: $0))
        }

        let sortedCashPoolStates = cashPoolStates.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.id.uuidString > rhs.id.uuidString
            }
            return lhs.updatedAt > rhs.updatedAt
        }
        let primaryCashPoolState = sortedCashPoolStates.first
        let duplicateStatesToDelete = Array(sortedCashPoolStates.dropFirst())
        let stateDecision = cashPoolStateDecision(
            transactions: transactions,
            missingDeltaValues: deltaValues,
            primaryState: primaryCashPoolState
        )

        let deltaRepairableCount = stateDecision.canRepair ? deltaValues.count : 0
        let deltaManualCount = emptyDeltaTransactions.count - deltaRepairableCount

        let findings = [
            DataHealthFinding(
                kind: .duplicateUUID,
                count: duplicateUUIDCount,
                repairableCount: duplicateUUIDRepairableCount,
                manualCount: duplicateUUIDManualCount,
                detail: duplicateUUIDCount == 0
                    ? "各数据类型内没有发现重复 UUID。"
                    : "能安全重新编号的记录会保留原数据；存在原始 ID 引用歧义的记录不会自动处理。"
            ),
            DataHealthFinding(
                kind: .orphanBudget,
                count: orphanBudgets.count,
                repairableCount: 0,
                manualCount: orphanBudgets.count,
                detail: orphanBudgets.isEmpty
                    ? "预算引用的分类均存在。没有账本关系的预算属于当前产品支持的全局预算。"
                    : "预算引用的分类已经不存在，未自动改成总预算，以避免改变预算含义。"
            ),
            DataHealthFinding(
                kind: .emptyTransactionDelta,
                count: emptyDeltaTransactions.count,
                repairableCount: deltaRepairableCount,
                manualCount: deltaManualCount,
                detail: deltaDetail(
                    emptyCount: emptyDeltaTransactions.count,
                    validCount: deltaValues.count,
                    canRepair: stateDecision.canRepair
                )
            ),
            DataHealthFinding(
                kind: .duplicateCashPoolState,
                count: duplicateStatesToDelete.count,
                repairableCount: duplicateStatesToDelete.count,
                manualCount: 0,
                detail: duplicateStatesToDelete.isEmpty
                    ? "资金池只有一个状态记录。"
                    : "保留最近更新的状态记录，不累加历史重复状态。"
            ),
            DataHealthFinding(
                kind: .missingLedger,
                count: missingLedgerTransactions.count,
                repairableCount: ledgerActions.count,
                manualCount: missingLedgerTransactions.count - ledgerActions.count,
                detail: missingLedgerTransactions.isEmpty
                    ? "所有交易都有账本归属。"
                    : "无账本交易会归入默认生活账本。"
            ),
            DataHealthFinding(
                kind: .uncategorizedTransaction,
                count: uncategorizedTransactions.count,
                repairableCount: 0,
                manualCount: uncategorizedTransactions.count,
                detail: uncategorizedTransactions.isEmpty
                    ? "所有交易都有分类。"
                    : "未自动猜测分类，避免根据备注或金额误改账目。"
            ),
            DataHealthFinding(
                kind: .invalidTransactionAmount,
                count: invalidAmountTransactions.count,
                repairableCount: 0,
                manualCount: invalidAmountTransactions.count,
                detail: invalidAmountTransactions.isEmpty
                    ? "没有发现非正交易金额。"
                    : "非正金额不会被自动改写。"
            )
        ]

        let plan = DataHealthRepairPlan(
            fingerprint: fingerprint,
            rekeyActions: rekeyActions,
            ledgerActions: ledgerActions,
            deltaActions: stateDecision.canRepair
                ? deltaValues.map { DataHealthDeltaAction(transaction: $0.0, value: $0.1) }
                : [],
            stateUpdate: stateDecision.update,
            newStateValue: stateDecision.newStateValue,
            duplicateStatesToDelete: duplicateStatesToDelete,
            defaultLedgerToInsert: defaultLedgerToInsert
        )

        return DataHealthReport(scannedAt: Date(), findings: findings, plan: plan)
    }

    func apply(_ plan: DataHealthRepairPlan) throws -> DataHealthApplyResult {
        let currentReport = try scan()
        guard currentReport.plan.fingerprint == plan.fingerprint else {
            throw DataHealthError.stalePreview
        }

        guard plan.hasChanges else {
            return DataHealthApplyResult(
                actionCount: 0,
                remainingManualIssueCount: currentReport.manualIssueCount
            )
        }

        do {
            if let defaultLedgerToInsert = plan.defaultLedgerToInsert {
                modelContext.insert(defaultLedgerToInsert)
            }

            for action in plan.rekeyActions {
                action.object.id = action.newID
            }

            for action in plan.ledgerActions {
                action.transaction.ledger = action.ledger
            }

            for action in plan.deltaActions {
                action.transaction.cashPoolDelta = action.value
            }

            if let stateUpdate = plan.stateUpdate {
                stateUpdate.state.transactionDelta = stateUpdate.value
                stateUpdate.state.updatedAt = Date()
            } else if let newStateValue = plan.newStateValue {
                modelContext.insert(CashPoolState(transactionDelta: newStateValue))
            }

            for state in plan.duplicateStatesToDelete {
                modelContext.delete(state)
            }

            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        let remainingReport = try scan()
        return DataHealthApplyResult(
            actionCount: plan.actionCount,
            remainingManualIssueCount: remainingReport.manualIssueCount
        )
    }

    private func duplicateUUIDResult(
        objects: [any DataHealthIdentifiedModel],
        recordType: DataHealthRecordType,
        incomingReferences: Set<RawReferenceKey>
    ) -> DuplicateScanResult {
        let groups = Dictionary(grouping: objects, by: { $0.id })
            .values
            .filter { $0.count > 1 }

        var actions: [DataHealthRekeyAction] = []
        var manualCount = 0
        var usedIDs = Set(objects.map(\.id))

        for group in groups {
            let duplicateCount = group.count - 1
            guard !incomingReferences.contains(RawReferenceKey(recordType: recordType, id: group[0].id)) else {
                manualCount += duplicateCount
                continue
            }

            for object in group.dropFirst() {
                let newID = uniqueID(avoiding: &usedIDs)
                actions.append(
                    DataHealthRekeyAction(
                        recordType: recordType,
                        object: object,
                        newID: newID
                    )
                )
            }
        }

        let count = groups.reduce(0) { $0 + $1.count - 1 }
        return DuplicateScanResult(
            count: count,
            repairableCount: actions.count,
            manualCount: manualCount,
            actions: actions
        )
    }

    private func uniqueID(avoiding usedIDs: inout Set<UUID>) -> UUID {
        var id = UUID()
        while usedIDs.contains(id) {
            id = UUID()
        }
        usedIDs.insert(id)
        return id
    }

    private func rawReferences(
        categories: [Category],
        recurringOccurrences: [RecurringOccurrence],
        budgets: [Budget]
    ) -> Set<RawReferenceKey> {
        var references = Set<RawReferenceKey>()

        for category in categories {
            if let targetID = category.mergedIntoCategoryID {
                references.insert(RawReferenceKey(recordType: .category, id: targetID))
            }
        }
        for occurrence in recurringOccurrences {
            references.insertIfPresent(
                recordType: .recurringRule,
                id: occurrence.ruleID
            )
            references.insertIfPresent(
                recordType: .transaction,
                id: occurrence.transactionID
            )
            references.insertIfPresent(
                recordType: .category,
                id: occurrence.categoryID
            )
            references.insertIfPresent(
                recordType: .ledger,
                id: occurrence.ledgerID
            )
        }
        for budget in budgets {
            references.insertIfPresent(
                recordType: .category,
                id: budget.categoryId
            )
        }
        return references
    }

    private struct CashPoolStateDecision {
        let canRepair: Bool
        let update: DataHealthStateUpdateAction?
        let newStateValue: Decimal?
    }

    private func cashPoolStateDecision(
        transactions: [Transaction],
        missingDeltaValues: [(Transaction, Decimal)],
        primaryState: CashPoolState?
    ) -> CashPoolStateDecision {
        guard !missingDeltaValues.isEmpty else {
            return CashPoolStateDecision(canRepair: true, update: nil, newStateValue: nil)
        }

        let knownDelta = transactions.reduce(Decimal.zero) { total, transaction in
            total + (transaction.cashPoolDelta ?? 0)
        }
        let missingDelta = missingDeltaValues.reduce(Decimal.zero) { total, item in
            total + item.1
        }
        let completeDelta = knownDelta + missingDelta

        guard let primaryState else {
            return CashPoolStateDecision(
                canRepair: true,
                update: nil,
                newStateValue: completeDelta
            )
        }

        if primaryState.transactionDelta == knownDelta {
            return CashPoolStateDecision(
                canRepair: true,
                update: DataHealthStateUpdateAction(
                    state: primaryState,
                    value: primaryState.transactionDelta + missingDelta
                ),
                newStateValue: nil
            )
        }

        if primaryState.transactionDelta == completeDelta {
            return CashPoolStateDecision(canRepair: true, update: nil, newStateValue: nil)
        }

        // A different value may represent a deliberate user calibration. We do
        // not guess whether the missing transaction delta was already included.
        return CashPoolStateDecision(canRepair: false, update: nil, newStateValue: nil)
    }

    private func deltaDetail(emptyCount: Int, validCount: Int, canRepair: Bool) -> String {
        guard emptyCount > 0 else { return "所有交易都记录了资金池 delta。" }
        if canRepair {
            return "\(validCount) 笔有效交易可以根据收支类型补齐；若资金池存在无法判断的人工校准，则保留为待人工确认。"
        }
        return "资金池状态与交易投影存在无法判断的差额，未自动修改，以避免覆盖人工校准。"
    }

    private func makeFingerprint(
        transactions: [Transaction],
        categories: [Category],
        ledgers: [Ledger],
        recurringRules: [RecurringRule],
        recurringOccurrences: [RecurringOccurrence],
        budgets: [Budget],
        physicalAssets: [PhysicalAsset],
        cashPoolItems: [CashPoolItem],
        cashPoolStates: [CashPoolState],
        savingsGoals: [SavingsGoal],
        installmentBills: [InstallmentBill],
        transactionTemplates: [TransactionTemplate],
        reminders: [Reminder]
    ) -> String {
        var lines: [String] = []

        lines.append(contentsOf: transactions.map { transaction in
            "transaction|\(transaction.id)|\(decimal(transaction.amount))|\(transaction.isExpense)|\(transaction.note)|\(transaction.date.timeIntervalSinceReferenceDate)|\(transaction.createdAt.timeIntervalSinceReferenceDate)|\(transaction.isPrivateIncome)|\(transaction.cashPoolDelta.map(decimal) ?? "nil")|\(transaction.dailyBudgetOverride.map(String.init) ?? "nil")|\(transaction.category?.id.uuidString ?? "nil")|\(transaction.ledger?.id.uuidString ?? "nil")|\(transaction.recurringRule?.id.uuidString ?? "nil")"
        })
        lines.append(contentsOf: categories.map { category in
            "category|\(category.id)|\(category.name)|\(category.icon)|\(category.colorHex)|\(category.isExpense)|\(category.sortOrder)|\(category.isArchived)|\(category.dailyBudgetOverride.map(String.init) ?? "nil")|\(category.parentCategoryName ?? "nil")|\(category.defaultKey ?? "nil")|\(category.mergedIntoCategoryID?.uuidString ?? "nil")"
        })
        lines.append(contentsOf: ledgers.map { ledger in
            "ledger|\(ledger.id)|\(ledger.name)|\(ledger.icon)|\(ledger.colorHex)|\(ledger.isDefault)|\(ledger.isArchived)|\(ledger.createdAt.timeIntervalSinceReferenceDate)|\(ledger.sortOrder)"
        })
        lines.append(contentsOf: recurringRules.map { rule in
            "recurringRule|\(rule.id)|\(rule.title)|\(decimal(rule.amount))|\(rule.isExpense)|\(rule.frequency.rawValue)|\(rule.nextDueDate.timeIntervalSinceReferenceDate)|\(rule.anchorDay.map(String.init) ?? "nil")|\(rule.endDate?.timeIntervalSinceReferenceDate.description ?? "nil")|\(rule.isActive)|\(rule.note)|\(rule.createdAt.timeIntervalSinceReferenceDate)|\(rule.category?.id.uuidString ?? "nil")|\(rule.ledger?.id.uuidString ?? "nil")"
        })
        lines.append(contentsOf: recurringOccurrences.map { occurrence in
            "recurringOccurrence|\(occurrence.id)|\(occurrence.occurrenceKey)|\(occurrence.ruleID)|\(occurrence.transactionID?.uuidString ?? "nil")|\(occurrence.scheduledDate.timeIntervalSinceReferenceDate)|\(occurrence.actualDate?.timeIntervalSinceReferenceDate.description ?? "nil")|\(decimal(occurrence.amount))|\(occurrence.isExpense)|\(occurrence.title)|\(occurrence.note)|\(occurrence.categoryID?.uuidString ?? "nil")|\(occurrence.ledgerID?.uuidString ?? "nil")|\(occurrence.status.rawValue)|\(occurrence.createdAt.timeIntervalSinceReferenceDate)|\(occurrence.resolvedAt?.timeIntervalSinceReferenceDate.description ?? "nil")"
        })
        lines.append(contentsOf: budgets.map { budget in
            "budget|\(budget.id)|\(decimal(budget.monthlyLimit))|\(budget.year)|\(budget.month)|\(budget.createdAt.timeIntervalSinceReferenceDate)|\(budget.ledger?.id.uuidString ?? "nil")|\(budget.categoryId?.uuidString ?? "nil")"
        })
        lines.append(contentsOf: physicalAssets.map { asset in
            "physicalAsset|\(asset.id)|\(asset.name)|\(asset.category.rawValue)|\(decimal(asset.purchasePrice))|\(asset.purchaseDate.timeIntervalSinceReferenceDate)|\(decimal(asset.salvageValue))|\(decimal(asset.targetDailyCost))|\(asset.soldPrice.map(decimal) ?? "nil")|\(asset.soldDate?.timeIntervalSinceReferenceDate.description ?? "nil")|\(asset.note)|\(asset.isArchived)"
        })
        lines.append(contentsOf: cashPoolItems.map { item in
            "cashPoolItem|\(item.id)|\(item.name)|\(item.kind.rawValue)|\(decimal(item.amount))|\(item.note)|\(item.isArchived)|\(item.sortOrder)|\(item.createdAt.timeIntervalSinceReferenceDate)|\(item.updatedAt.timeIntervalSinceReferenceDate)"
        })
        lines.append(contentsOf: cashPoolStates.map { state in
            "cashPoolState|\(state.id)|\(decimal(state.transactionDelta))|\(state.updatedAt.timeIntervalSinceReferenceDate)"
        })
        lines.append(contentsOf: savingsGoals.map { goal in
            "savingsGoal|\(goal.id)|\(goal.name)|\(decimal(goal.targetAmount))|\(decimal(goal.currentAmount))|\(goal.targetDate?.timeIntervalSinceReferenceDate.description ?? "nil")|\(goal.note)|\(goal.isCompleted)|\(goal.isArchived)|\(goal.createdAt.timeIntervalSinceReferenceDate)|\(goal.updatedAt.timeIntervalSinceReferenceDate)"
        })
        lines.append(contentsOf: installmentBills.map { bill in
            "installmentBill|\(bill.id)|\(bill.name)|\(decimal(bill.totalAmount))|\(bill.installmentCount)|\(bill.paidInstallments)|\(bill.repaymentDay)|\(bill.firstRepaymentDate.timeIntervalSinceReferenceDate)|\(bill.note)|\(bill.isArchived)|\(bill.createdAt.timeIntervalSinceReferenceDate)|\(bill.updatedAt.timeIntervalSinceReferenceDate)"
        })
        lines.append(contentsOf: transactionTemplates.map { template in
            "transactionTemplate|\(template.id)|\(template.name)|\(decimal(template.amount))|\(template.isExpense)|\(template.note)|\(template.categoryName ?? "nil")|\(template.sortOrder)"
        })
        lines.append(contentsOf: reminders.map { reminder in
            "reminder|\(reminder.id)|\(reminder.title)|\(reminder.note)|\(reminder.dueDate.timeIntervalSinceReferenceDate)|\(reminder.intensityRawValue)|\(reminder.isCompleted)|\(reminder.createdAt.timeIntervalSinceReferenceDate)|\(reminder.completedAt?.timeIntervalSinceReferenceDate.description ?? "nil")"
        })

        return lines.sorted().joined(separator: "\n")
    }

    private func decimal(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}

private extension Set where Element == DataHealthService.RawReferenceKey {
    mutating func insertIfPresent(recordType: DataHealthRecordType, id: UUID?) {
        guard let id else { return }
        insert(DataHealthService.RawReferenceKey(recordType: recordType, id: id))
    }
}
