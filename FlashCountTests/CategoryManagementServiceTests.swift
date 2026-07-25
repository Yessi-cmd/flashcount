import XCTest
import SwiftData
@testable import FlashCount

@MainActor
final class CategoryManagementServiceTests: XCTestCase {
    func testRenamingRootUpdatesChildrenAndTemplatesAtomically() throws {
        let context = try makeContext()
        let root = Category(name: "餐饮", icon: "fork.knife", colorHex: "#FF0000", sortOrder: 0)
        let child = Category(
            name: "咖啡",
            icon: "cup.and.saucer.fill",
            colorHex: "#AA0000",
            sortOrder: 1,
            parentCategoryName: "餐饮"
        )
        let template = TransactionTemplate(name: "午餐", amount: 20, categoryName: "餐饮")
        context.insert(root)
        context.insert(child)
        context.insert(template)
        try context.save()

        try CategoryManagementService(modelContext: context).update(
            root,
            name: "吃喝",
            icon: "takeoutbag.and.cup.and.straw.fill",
            colorHex: "#00AA00",
            parent: nil
        )

        XCTAssertEqual(root.name, "吃喝")
        XCTAssertEqual(child.parentCategoryName, "吃喝")
        XCTAssertEqual(child.rootCategoryName, "吃喝")
        XCTAssertEqual(template.categoryName, "吃喝")
    }

    func testMergeMigratesReferencesAndCombinesMatchingBudgets() throws {
        let context = try makeContext()
        let target = Category(name: "餐饮", icon: "fork.knife", colorHex: "#FF0000", sortOrder: 0)
        let source = Category(
            name: "咖啡",
            icon: "cup.and.saucer.fill",
            colorHex: "#AA0000",
            sortOrder: 1,
            parentCategoryName: "餐饮"
        )
        let transaction = Transaction(amount: 20, category: source)
        let rule = RecurringRule(title: "咖啡月卡", amount: 30, nextDueDate: Date(), category: source)
        let sourceBudget = Budget(monthlyLimit: 500, year: 2026, month: 7, categoryId: source.id)
        let targetBudget = Budget(monthlyLimit: 1_000, year: 2026, month: 7, categoryId: target.id)
        let template = TransactionTemplate(name: "咖啡", amount: 18, categoryName: source.name)
        [target, source].forEach(context.insert)
        context.insert(transaction)
        context.insert(rule)
        context.insert(sourceBudget)
        context.insert(targetBudget)
        context.insert(template)
        try context.save()

        try CategoryManagementService(modelContext: context).merge(source, into: target)

        XCTAssertTrue(source.isArchived)
        XCTAssertEqual(source.mergedIntoCategoryID, target.id)
        XCTAssertEqual(transaction.category?.id, target.id)
        XCTAssertEqual(rule.category?.id, target.id)
        XCTAssertEqual(template.categoryName, target.name)
        let budgets = try context.fetch(FetchDescriptor<Budget>())
        XCTAssertEqual(budgets.count, 1)
        XCTAssertEqual(budgets.first?.categoryId, target.id)
        XCTAssertEqual(budgets.first?.monthlyLimit, 1_500)
    }

    func testArchivingAndRestoringRootCascadesToChildren() throws {
        let context = try makeContext()
        let root = Category(name: "餐饮", icon: "fork.knife", colorHex: "#FF0000", sortOrder: 0)
        let otherRoot = Category(name: "购物", icon: "bag.fill", colorHex: "#00AA00", sortOrder: 100)
        let child = Category(
            name: "咖啡",
            icon: "cup.and.saucer.fill",
            colorHex: "#AA0000",
            sortOrder: 1,
            parentCategoryName: "餐饮"
        )
        [root, otherRoot, child].forEach(context.insert)
        try context.save()
        let service = CategoryManagementService(modelContext: context)

        try service.archive(root)
        XCTAssertTrue(root.isArchived)
        XCTAssertTrue(child.isArchived)

        try service.restore(root)
        XCTAssertFalse(root.isArchived)
        XCTAssertFalse(child.isArchived)
    }

    func testCannotArchiveLastActiveRoot() throws {
        let context = try makeContext()
        let onlyRoot = Category(name: "唯一分类", icon: "tag.fill", colorHex: "#000000")
        context.insert(onlyRoot)
        try context.save()

        XCTAssertThrowsError(try CategoryManagementService(modelContext: context).archive(onlyRoot)) { error in
            XCTAssertEqual(error as? CategoryManagementError, .lastActiveCategory)
        }
        XCTAssertFalse(onlyRoot.isArchived)
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
