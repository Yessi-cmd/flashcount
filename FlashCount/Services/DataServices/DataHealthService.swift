import Foundation
import SwiftData

/// 体检修复被拒绝的原因。`stalePreview` 表示预览之后数据变过，
/// 此时执行会落在与预览不同的数据上。
enum DataHealthError: LocalizedError, Equatable {
    case stalePreview

    var errorDescription: String? {
        switch self {
        case .stalePreview:
            return "本地数据在预览后发生了变化，请重新扫描。"
        }
    }
}

/// 本地数据体检与修复。
///
/// 只读地扫描出问题、给出修复方案，执行前用数据指纹确认数据未变。
/// 刻意保守：能安全自动处理的才自动处理（重新编号、补账本归属、补资金增减），
/// 涉及语义判断的（孤儿预算、未分类交易、非正金额）一律只报告不改写——
/// 猜错比不猜更糟。
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

    /// `scan()` 读到的一整份本地数据。原先这十三个数组是 `scan()` 的局部变量，
    /// 各项检查也都写在同一个函数体里，加起来 203 行；拆开后每项检查能单独读，
    /// findings 的组装也不再和检查逻辑交织。
    private struct Snapshot {
        let transactions: [Transaction]
        let categories: [Category]
        let ledgers: [Ledger]
        let recurringRules: [RecurringRule]
        let recurringOccurrences: [RecurringOccurrence]
        let budgets: [Budget]
        let physicalAssets: [PhysicalAsset]
        let cashPoolItems: [CashPoolItem]
        let cashPoolStates: [CashPoolState]
        let savingsGoals: [SavingsGoal]
        let installmentBills: [InstallmentBill]
        let transactionTemplates: [TransactionTemplate]
        let reminders: [Reminder]
    }

    /// 重复 UUID 检查在所有类型上的合计。
    private struct DuplicateTotals {
        var count = 0
        var repairableCount = 0
        var manualCount = 0
        var actions: [DataHealthRekeyAction] = []
    }

    /// 无账本交易的归属修复。`defaultLedgerToInsert` 非空表示连默认账本都得先建。
    private struct LedgerRepair {
        let missingTransactions: [Transaction]
        let actions: [DataHealthLedgerAction]
        let defaultLedgerToInsert: Ledger?
    }

    /// 资金池增减缺失的修复，连同要保留／删除哪个状态记录的决定。
    private struct DeltaRepair {
        let emptyCount: Int
        let values: [(Transaction, Decimal)]
        let repairableCount: Int
        let manualCount: Int
        let decision: CashPoolStateDecision
        let duplicateStatesToDelete: [CashPoolState]
    }

    /// 交易之外各财务模型的金额约束。旧备份或历史版本可能绕过当前输入校验，
    /// 因此体检不能只检查 `Transaction.amount`。
    private struct InvalidFinancialAmountTotals {
        let recurringRules: Int
        let cashPoolItems: Int
        let budgets: Int
        let savingsGoals: Int
        let installmentBills: Int

        var count: Int {
            recurringRules + cashPoolItems + budgets + savingsGoals + installmentBills
        }

        var detail: String {
            guard count > 0 else {
                return "周期规则、资金项、预算、储蓄目标和分期金额均符合约束。"
            }
            let parts: [String] = [
                recurringRules > 0 ? "周期规则 \(recurringRules)" : nil,
                cashPoolItems > 0 ? "资金项 \(cashPoolItems)" : nil,
                budgets > 0 ? "预算 \(budgets)" : nil,
                savingsGoals > 0 ? "储蓄目标 \(savingsGoals)" : nil,
                installmentBills > 0 ? "分期 \(installmentBills)" : nil,
            ].compactMap { $0 }
            return "发现无效金额：\(parts.joined(separator: "、"))。这些金额不会被自动改写。"
        }
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func scan() throws -> DataHealthReport {
        let snapshot = try fetchSnapshot()
        let fingerprint = makeFingerprint(snapshot)
        let duplicates = duplicateTotals(in: snapshot)
        let orphanBudgets = orphanBudgets(in: snapshot)
        let ledgerRepair = ledgerRepair(in: snapshot)
        let deltaRepair = deltaRepair(in: snapshot)

        let findings = makeFindings(
            snapshot: snapshot,
            duplicates: duplicates,
            orphanBudgets: orphanBudgets,
            ledgerRepair: ledgerRepair,
            deltaRepair: deltaRepair
        )

        let plan = DataHealthRepairPlan(
            fingerprint: fingerprint,
            rekeyActions: duplicates.actions,
            ledgerActions: ledgerRepair.actions,
            deltaActions: deltaRepair.decision.canRepair
                ? deltaRepair.values.map { DataHealthDeltaAction(transaction: $0.0, value: $0.1) }
                : [],
            stateUpdate: deltaRepair.decision.update,
            newStateValue: deltaRepair.decision.newStateValue,
            duplicateStatesToDelete: deltaRepair.duplicateStatesToDelete,
            defaultLedgerToInsert: ledgerRepair.defaultLedgerToInsert
        )

        return DataHealthReport(scannedAt: Date(), findings: findings, plan: plan)
    }

    // MARK: - 扫描各步骤

    private func fetchSnapshot() throws -> Snapshot {
        Snapshot(
            transactions: try modelContext.fetch(FetchDescriptor<Transaction>()),
            categories: try modelContext.fetch(FetchDescriptor<Category>()),
            ledgers: try modelContext.fetch(FetchDescriptor<Ledger>()),
            recurringRules: try modelContext.fetch(FetchDescriptor<RecurringRule>()),
            recurringOccurrences: try modelContext.fetch(FetchDescriptor<RecurringOccurrence>()),
            budgets: try modelContext.fetch(FetchDescriptor<Budget>()),
            physicalAssets: try modelContext.fetch(FetchDescriptor<PhysicalAsset>()),
            cashPoolItems: try modelContext.fetch(FetchDescriptor<CashPoolItem>()),
            cashPoolStates: try modelContext.fetch(FetchDescriptor<CashPoolState>()),
            savingsGoals: try modelContext.fetch(FetchDescriptor<SavingsGoal>()),
            installmentBills: try modelContext.fetch(FetchDescriptor<InstallmentBill>()),
            transactionTemplates: try modelContext.fetch(FetchDescriptor<TransactionTemplate>()),
            reminders: try modelContext.fetch(FetchDescriptor<Reminder>())
        )
    }

    private func duplicateTotals(in snapshot: Snapshot) -> DuplicateTotals {
        let incomingReferences = rawReferences(
            categories: snapshot.categories,
            recurringOccurrences: snapshot.recurringOccurrences,
            budgets: snapshot.budgets
        )

        let collections: [(DataHealthRecordType, [any DataHealthIdentifiedModel])] = [
            (.transaction, snapshot.transactions),
            (.category, snapshot.categories),
            (.ledger, snapshot.ledgers),
            (.recurringRule, snapshot.recurringRules),
            (.recurringOccurrence, snapshot.recurringOccurrences),
            (.budget, snapshot.budgets),
            (.physicalAsset, snapshot.physicalAssets),
            (.cashPoolItem, snapshot.cashPoolItems),
            (.savingsGoal, snapshot.savingsGoals),
            (.installmentBill, snapshot.installmentBills),
            (.transactionTemplate, snapshot.transactionTemplates),
            (.reminder, snapshot.reminders)
        ]

        var totals = DuplicateTotals()
        for (recordType, objects) in collections {
            let result = duplicateUUIDResult(
                objects: objects,
                recordType: recordType,
                incomingReferences: incomingReferences
            )
            totals.count += result.count
            totals.repairableCount += result.repairableCount
            totals.manualCount += result.manualCount
            totals.actions.append(contentsOf: result.actions)
        }
        return totals
    }

    private func orphanBudgets(in snapshot: Snapshot) -> [Budget] {
        snapshot.budgets.filter { budget in
            guard let categoryID = budget.categoryId else { return false }
            return !snapshot.categories.contains { $0.id == categoryID }
        }
    }

    private func ledgerRepair(in snapshot: Snapshot) -> LedgerRepair {
        let missingTransactions = snapshot.transactions.filter { $0.ledger == nil }
        let defaultLedger = snapshot.ledgers.first(where: { $0.isDefault }) ?? snapshot.ledgers.first

        let ledgerForRepair: Ledger?
        let defaultLedgerToInsert: Ledger?
        if let defaultLedger {
            ledgerForRepair = defaultLedger
            defaultLedgerToInsert = nil
        } else if !missingTransactions.isEmpty {
            // 一个账本都没有时，修复需要连默认账本一起建出来。
            let createdLedger = Ledger.defaultLedgers()[0]
            ledgerForRepair = createdLedger
            defaultLedgerToInsert = createdLedger
        } else {
            ledgerForRepair = nil
            defaultLedgerToInsert = nil
        }

        let actions = missingTransactions.compactMap { transaction -> DataHealthLedgerAction? in
            guard let ledgerForRepair else { return nil }
            return DataHealthLedgerAction(transaction: transaction, ledger: ledgerForRepair)
        }

        return LedgerRepair(
            missingTransactions: missingTransactions,
            actions: actions,
            defaultLedgerToInsert: defaultLedgerToInsert
        )
    }

    private func deltaRepair(in snapshot: Snapshot) -> DeltaRepair {
        let emptyDeltaTransactions = snapshot.transactions.filter { $0.cashPoolDelta == nil }
        let values = emptyDeltaTransactions
            .filter { $0.amount > 0 }
            .map { ($0, CashPoolService.transactionDelta(for: $0)) }

        // 只保留最近更新的状态记录；相同时间戳按 UUID 定序，避免结果随机。
        let sortedStates = snapshot.cashPoolStates.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.id.uuidString > rhs.id.uuidString
            }
            return lhs.updatedAt > rhs.updatedAt
        }

        let decision = cashPoolStateDecision(
            transactions: snapshot.transactions,
            missingDeltaValues: values,
            primaryState: sortedStates.first
        )
        let repairableCount = decision.canRepair ? values.count : 0

        return DeltaRepair(
            emptyCount: emptyDeltaTransactions.count,
            values: values,
            repairableCount: repairableCount,
            manualCount: emptyDeltaTransactions.count - repairableCount,
            decision: decision,
            duplicateStatesToDelete: Array(sortedStates.dropFirst())
        )
    }

    private func makeFindings(
        snapshot: Snapshot,
        duplicates: DuplicateTotals,
        orphanBudgets: [Budget],
        ledgerRepair: LedgerRepair,
        deltaRepair: DeltaRepair
    ) -> [DataHealthFinding] {
        let invalidAmountTransactions = snapshot.transactions.filter { $0.amount <= 0 }
        let invalidFinancialAmounts = invalidFinancialAmountTotals(in: snapshot)
        let uncategorizedTransactions = snapshot.transactions.filter { $0.category == nil }
        let duplicateUUIDCount = duplicates.count
        let missingLedgerTransactions = ledgerRepair.missingTransactions
        let ledgerActions = ledgerRepair.actions
        let duplicateStatesToDelete = deltaRepair.duplicateStatesToDelete

        return [
            DataHealthFinding(
                kind: .duplicateUUID,
                count: duplicateUUIDCount,
                repairableCount: duplicates.repairableCount,
                manualCount: duplicates.manualCount,
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
                count: deltaRepair.emptyCount,
                repairableCount: deltaRepair.repairableCount,
                manualCount: deltaRepair.manualCount,
                detail: deltaDetail(
                    emptyCount: deltaRepair.emptyCount,
                    validCount: deltaRepair.values.count,
                    canRepair: deltaRepair.decision.canRepair
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
            ),
            DataHealthFinding(
                kind: .invalidFinancialAmount,
                count: invalidFinancialAmounts.count,
                repairableCount: 0,
                manualCount: invalidFinancialAmounts.count,
                detail: invalidFinancialAmounts.detail
            )
        ]
    }

    private func invalidFinancialAmountTotals(
        in snapshot: Snapshot
    ) -> InvalidFinancialAmountTotals {
        InvalidFinancialAmountTotals(
            recurringRules: snapshot.recurringRules.count(where: { $0.amount <= 0 }),
            cashPoolItems: snapshot.cashPoolItems.count(where: { $0.amount <= 0 }),
            budgets: snapshot.budgets.count(where: { $0.monthlyLimit <= 0 }),
            savingsGoals: snapshot.savingsGoals.count(where: {
                $0.targetAmount <= 0 || $0.currentAmount < 0
            }),
            installmentBills: snapshot.installmentBills.count(where: { $0.totalAmount <= 0 })
        )
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

    /// 指纹覆盖每个模型的每个字段：预览与实际执行之间只要有一处变化就必须让
    /// `apply` 拒绝，否则修复会作用在用户已经改过的数据上。
    private func makeFingerprint(_ snapshot: Snapshot) -> String {
        let transactions = snapshot.transactions
        let categories = snapshot.categories
        let ledgers = snapshot.ledgers
        let recurringRules = snapshot.recurringRules
        let recurringOccurrences = snapshot.recurringOccurrences
        let budgets = snapshot.budgets
        let physicalAssets = snapshot.physicalAssets
        let cashPoolItems = snapshot.cashPoolItems
        let cashPoolStates = snapshot.cashPoolStates
        let savingsGoals = snapshot.savingsGoals
        let installmentBills = snapshot.installmentBills
        let transactionTemplates = snapshot.transactionTemplates
        let reminders = snapshot.reminders

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
