import XCTest
import SwiftData
@testable import FlashCount

/// Regression coverage for single-ledger consolidation. `Ledger` cascades
/// deletes to transactions and budgets, so the consolidation path must never
/// reduce the number of user records under any input.
@MainActor
final class LedgerConsolidationTests: XCTestCase {
    func testConsolidationPreservesEveryTransactionAndBudget() throws {
        let context = try makeContext()
        let life = Ledger(name: "生活", icon: "house.fill", colorHex: "#4E766A", isDefault: true)
        let travel = Ledger(name: "旅行", icon: "airplane", colorHex: "#4EA8F8", sortOrder: 1)
        let work = Ledger(name: "工作", icon: "briefcase.fill", colorHex: "#F8B84E", sortOrder: 2)
        context.insert(life)
        context.insert(travel)
        context.insert(work)

        context.insert(Transaction(amount: 10, note: "life", ledger: life))
        context.insert(Transaction(amount: 20, note: "travel", ledger: travel))
        context.insert(Transaction(amount: 30, note: "work", ledger: work))
        context.insert(Transaction(amount: 40, note: "orphan"))
        context.insert(Budget(monthlyLimit: 1_000, year: 2026, month: 7, ledger: travel))
        context.insert(Budget(monthlyLimit: 2_000, year: 2026, month: 7, ledger: life))
        context.insert(RecurringRule(
            title: "房租",
            amount: 1_500,
            frequency: .monthly,
            nextDueDate: Date().addingTimeInterval(86_400),
            ledger: work
        ))
        try context.save()

        try DefaultDataService(modelContext: context).stageDefaultData()
        try context.save()

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let budgets = try context.fetch(FetchDescriptor<Budget>())
        let ledgers = try context.fetch(FetchDescriptor<Ledger>())
        let rules = try context.fetch(FetchDescriptor<RecurringRule>())

        XCTAssertEqual(transactions.count, 4, "整理不得减少任何一笔交易")
        XCTAssertEqual(budgets.count, 2, "整理不得删除预算，只能解除账本绑定")
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(ledgers.count, 1)
        XCTAssertEqual(ledgers.first?.name, "生活")
        XCTAssertTrue(transactions.allSatisfy { $0.ledger?.id == ledgers.first?.id })
        XCTAssertTrue(budgets.allSatisfy { $0.ledger == nil })
        XCTAssertEqual(rules.first?.ledger?.id, ledgers.first?.id)
    }

    func testConsolidationIsIdempotent() throws {
        let context = try makeContext()
        let life = Ledger(name: "生活", icon: "house.fill", colorHex: "#4E766A", isDefault: true)
        let travel = Ledger(name: "旅行", icon: "airplane", colorHex: "#4EA8F8", sortOrder: 1)
        context.insert(life)
        context.insert(travel)
        context.insert(Transaction(amount: 5, note: "a", ledger: travel))
        try context.save()

        let service = DefaultDataService(modelContext: context)
        try service.stageDefaultData()
        try context.save()
        try service.stageDefaultData()
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Transaction>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Ledger>()).count, 1)
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Transaction.self,
            Category.self,
            Ledger.self,
            RecurringRule.self,
            RecurringOccurrence.self,
            Budget.self,
            Asset.self,
            PhysicalAsset.self,
            CashPoolItem.self,
            CashPoolState.self,
            SavingsGoal.self,
            InstallmentBill.self,
            TransactionTemplate.self,
            Reminder.self,
            configurations: configuration
        )
        return ModelContext(container)
    }
}
