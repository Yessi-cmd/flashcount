import SwiftData
import XCTest
@testable import FlashCount

@MainActor
final class DataHealthServiceTests: XCTestCase {
    func testScanIsReadOnlyAndReportsRequestedIssues() throws {
        let context = try makeContext()
        let ledger = Ledger(name: "生活", icon: "house.fill", colorHex: "#4E766A", isDefault: true)
        context.insert(ledger)

        let incompleteTransaction = Transaction(amount: 12, note: "缺 delta", category: nil, ledger: nil)
        context.insert(incompleteTransaction)

        let duplicateFirst = Transaction(amount: 3, note: "重复一", cashPoolDelta: -3, ledger: ledger)
        let duplicateSecond = Transaction(amount: 4, note: "重复二", cashPoolDelta: -4, ledger: ledger)
        duplicateSecond.id = duplicateFirst.id
        context.insert(duplicateFirst)
        context.insert(duplicateSecond)

        let orphanBudget = Budget(monthlyLimit: 100, year: 2026, month: 7, categoryId: UUID())
        context.insert(orphanBudget)
        context.insert(CashPoolState(transactionDelta: 0))
        context.insert(CashPoolState(transactionDelta: 0))
        try context.save()

        let originalDelta = incompleteTransaction.cashPoolDelta
        let originalStateCount = try context.fetchCount(FetchDescriptor<CashPoolState>())
        let report = try DataHealthService(modelContext: context).scan()

        XCTAssertNil(originalDelta)
        XCTAssertNil(incompleteTransaction.cashPoolDelta)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CashPoolState>()), originalStateCount)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(finding(.emptyTransactionDelta, in: report).count, 1)
        XCTAssertEqual(finding(.orphanBudget, in: report).count, 1)
        XCTAssertEqual(finding(.duplicateCashPoolState, in: report).count, 1)
        XCTAssertEqual(finding(.duplicateUUID, in: report).count, 1)
        XCTAssertTrue(report.hasRepairableIssues)
    }

    func testApplyRepairsMissingDeltaAndConsolidatesCashPoolStates() throws {
        let context = try makeContext()
        let ledger = Ledger(name: "生活", icon: "house.fill", colorHex: "#4E766A", isDefault: true)
        context.insert(ledger)

        let transaction = Transaction(amount: 12, ledger: ledger)
        context.insert(transaction)
        let oldState = CashPoolState(transactionDelta: 0)
        oldState.updatedAt = Date(timeIntervalSince1970: 100)
        let newestState = CashPoolState(transactionDelta: 0)
        newestState.updatedAt = Date(timeIntervalSince1970: 200)
        context.insert(oldState)
        context.insert(newestState)
        try context.save()

        let service = DataHealthService(modelContext: context)
        let report = try service.scan()
        let result = try service.apply(report.plan)

        XCTAssertGreaterThan(result.actionCount, 0)
        XCTAssertEqual(transaction.cashPoolDelta, -12)
        let states = try context.fetch(FetchDescriptor<CashPoolState>())
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states.first?.id, newestState.id)
        XCTAssertEqual(states.first?.transactionDelta, -12)

        let rescanned = try service.scan()
        XCTAssertEqual(finding(.emptyTransactionDelta, in: rescanned).count, 0)
        XCTAssertEqual(finding(.duplicateCashPoolState, in: rescanned).count, 0)
    }

    func testOrphanBudgetIsReportedButNotAutomaticallyChanged() throws {
        let context = try makeContext()
        let missingCategoryID = UUID()
        let budget = Budget(monthlyLimit: 300, year: 2026, month: 7, categoryId: missingCategoryID)
        context.insert(budget)
        try context.save()

        let service = DataHealthService(modelContext: context)
        let report = try service.scan()

        XCTAssertEqual(finding(.orphanBudget, in: report).count, 1)
        XCTAssertEqual(finding(.orphanBudget, in: report).repairableCount, 0)
        XCTAssertFalse(report.hasRepairableIssues)

        _ = try service.apply(report.plan)
        XCTAssertEqual(budget.categoryId, missingCategoryID)
    }

    func testDuplicateUUIDWithRawReferenceRequiresManualReview() throws {
        let context = try makeContext()
        let first = Category(name: "第一分类", icon: "tag", colorHex: "#123456")
        let second = Category(name: "第二分类", icon: "tag", colorHex: "#654321")
        second.id = first.id
        context.insert(first)
        context.insert(second)

        let budget = Budget(monthlyLimit: 100, year: 2026, month: 7, categoryId: first.id)
        context.insert(budget)
        try context.save()

        let report = try DataHealthService(modelContext: context).scan()
        let duplicateFinding = finding(.duplicateUUID, in: report)

        XCTAssertEqual(duplicateFinding.count, 1)
        XCTAssertEqual(duplicateFinding.repairableCount, 0)
        XCTAssertEqual(duplicateFinding.manualCount, 1)
        XCTAssertFalse(report.hasRepairableIssues)
    }

    func testApplyRekeysDuplicateUUIDWithoutRawReference() throws {
        let context = try makeContext()
        let first = CashPoolItem(name: "现金账户", kind: .cash, amount: 100)
        let second = CashPoolItem(name: "备用现金", kind: .cash, amount: 50)
        second.id = first.id
        context.insert(first)
        context.insert(second)
        try context.save()

        let service = DataHealthService(modelContext: context)
        let report = try service.scan()
        let duplicateFinding = finding(.duplicateUUID, in: report)

        XCTAssertEqual(duplicateFinding.count, 1)
        XCTAssertEqual(duplicateFinding.repairableCount, 1)
        XCTAssertEqual(duplicateFinding.manualCount, 0)

        _ = try service.apply(report.plan)

        let items = try context.fetch(FetchDescriptor<CashPoolItem>())
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(Set(items.map(\.id)).count, 2)
        XCTAssertEqual(finding(.duplicateUUID, in: try service.scan()).count, 0)
    }

    func testStalePreviewIsRejectedWithoutApplying() throws {
        let context = try makeContext()
        let ledger = Ledger(name: "生活", icon: "house.fill", colorHex: "#4E766A", isDefault: true)
        context.insert(ledger)
        let transaction = Transaction(amount: 12, ledger: ledger)
        context.insert(transaction)
        try context.save()

        let service = DataHealthService(modelContext: context)
        let report = try service.scan()
        transaction.note = "预览后修改"

        XCTAssertThrowsError(try service.apply(report.plan)) { error in
            XCTAssertEqual(error as? DataHealthError, .stalePreview)
        }
        XCTAssertNil(transaction.cashPoolDelta)
    }

    private func finding(_ kind: DataHealthIssueKind, in report: DataHealthReport) -> DataHealthFinding {
        if let finding = report.findings.first(where: { $0.kind == kind }) {
            return finding
        }
        XCTFail("缺少检查项：\(kind.title)")
        return DataHealthFinding(
            kind: kind,
            count: 0,
            repairableCount: 0,
            manualCount: 0,
            detail: ""
        )
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Transaction.self,
            Category.self,
            Ledger.self,
            RecurringRule.self,
            Budget.self,
            PhysicalAsset.self,
            CashPoolItem.self,
            CashPoolState.self,
            SavingsGoal.self,
            InstallmentBill.self,
            TransactionTemplate.self,
            Reminder.self,
            RecurringOccurrence.self,
            configurations: configuration
        )
        return ModelContext(container)
    }
}
