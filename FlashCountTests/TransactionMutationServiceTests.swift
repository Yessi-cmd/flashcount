import SwiftData
import XCTest
@testable import FlashCount

@MainActor
final class TransactionMutationServiceTests: XCTestCase {
    func testCreateAndUpdateCommitTransactionWithCashPoolProjection() throws {
        let context = try makeContext()
        let salary = Category(name: "工资", icon: "banknote", colorHex: "#00AA00", isExpense: false)
        context.insert(salary)
        try context.save()

        let service = TransactionMutationService(modelContext: context)
        let transaction = try service.create(TransactionDraft(amount: 25, isExpense: true, note: "午餐"))

        XCTAssertEqual(transaction.cashPoolDelta, -25)
        XCTAssertEqual(try cashPoolState(in: context).transactionDelta, -25)

        try service.update(
            transaction,
            with: TransactionDraft(
                amount: 40,
                isExpense: false,
                note: "工资",
                dailyBudgetOverride: true,
                category: salary
            )
        )

        XCTAssertEqual(transaction.cashPoolDelta, 40)
        XCTAssertEqual(transaction.dailyBudgetOverride, nil)
        XCTAssertTrue(transaction.isPrivateIncome)
        XCTAssertEqual(try cashPoolState(in: context).transactionDelta, 40)
    }

    func testDeleteAndRestorePreserveIdentityAndFinancialState() throws {
        let context = try makeContext()
        let service = TransactionMutationService(modelContext: context)
        let transaction = try service.create(TransactionDraft(amount: 12.34, isExpense: true))
        let originalID = transaction.id
        let originalCreatedAt = transaction.createdAt

        let snapshot = try service.delete(transaction)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 0)
        XCTAssertEqual(try cashPoolState(in: context).transactionDelta, 0)

        let restored = try service.restore(snapshot)

        XCTAssertEqual(restored.id, originalID)
        XCTAssertEqual(restored.createdAt, originalCreatedAt)
        XCTAssertEqual(restored.cashPoolDelta, Decimal(string: "-12.34"))
        XCTAssertEqual(try cashPoolState(in: context).transactionDelta, Decimal(string: "-12.34"))
    }

    func testBatchDeleteAppliesOneConsistentCashPoolResult() throws {
        let context = try makeContext()
        let service = TransactionMutationService(modelContext: context)
        let expense = try service.create(TransactionDraft(amount: 30, isExpense: true))
        let income = try service.create(TransactionDraft(amount: 10, isExpense: false))

        try service.delete([expense, income, expense])

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 0)
        XCTAssertEqual(try cashPoolState(in: context).transactionDelta, 0)
    }

    func testInvalidDraftDoesNotCreatePersistedState() throws {
        let context = try makeContext()
        let service = TransactionMutationService(modelContext: context)

        XCTAssertThrowsError(try service.create(TransactionDraft(amount: 0, isExpense: true))) { error in
            XCTAssertEqual(error as? TransactionMutationError, .invalidAmount)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CashPoolState>()), 0)
    }

    private func cashPoolState(in context: ModelContext) throws -> CashPoolState {
        try XCTUnwrap(context.fetch(FetchDescriptor<CashPoolState>()).first)
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Transaction.self,
            Category.self,
            Ledger.self,
            RecurringRule.self,
            Budget.self,
            Asset.self,
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
