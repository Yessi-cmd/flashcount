import XCTest
import SwiftData
@testable import FlashCount

@MainActor
final class SavingsGoalServiceTests: XCTestCase {
    func testDepositAdvancesProgressAndCompletesOnReachingTarget() throws {
        let context = try makeContext()
        let goal = SavingsGoal(name: "应急金", targetAmount: 1_000, currentAmount: 200)
        context.insert(goal)
        try context.save()

        let service = SavingsGoalService(modelContext: context)
        try service.deposit(300, into: goal)

        XCTAssertEqual(goal.currentAmount, 500)
        XCTAssertFalse(goal.isCompleted)
        XCTAssertEqual(goal.remainingAmount, 500)

        try service.deposit(500, into: goal)
        XCTAssertEqual(goal.currentAmount, 1_000)
        XCTAssertTrue(goal.isCompleted, "存满目标应自动标记完成")
        XCTAssertEqual(goal.remainingAmount, 0)
    }

    func testWithdrawReducesProgressAndReopensCompletedGoal() throws {
        let context = try makeContext()
        let goal = SavingsGoal(name: "应急金", targetAmount: 1_000, currentAmount: 1_000)
        context.insert(goal)
        try context.save()
        XCTAssertTrue(goal.isCompleted)

        try SavingsGoalService(modelContext: context).withdraw(400, from: goal)

        XCTAssertEqual(goal.currentAmount, 600)
        XCTAssertFalse(goal.isCompleted, "取出后不再满足目标，完成状态应撤回")
    }

    func testWithdrawCannotExceedSavedAmount() throws {
        let context = try makeContext()
        let goal = SavingsGoal(name: "应急金", targetAmount: 1_000, currentAmount: 100)
        context.insert(goal)
        try context.save()

        XCTAssertThrowsError(try SavingsGoalService(modelContext: context).withdraw(200, from: goal))
        XCTAssertEqual(goal.currentAmount, 100, "校验失败不得改动已存金额")
    }

    func testNonPositiveAmountsAreRejected() throws {
        let context = try makeContext()
        let goal = SavingsGoal(name: "应急金", targetAmount: 1_000, currentAmount: 100)
        context.insert(goal)
        try context.save()

        let service = SavingsGoalService(modelContext: context)
        XCTAssertThrowsError(try service.deposit(0, into: goal))
        XCTAssertThrowsError(try service.withdraw(-50, from: goal))
        XCTAssertEqual(goal.currentAmount, 100)
    }

    /// 存钱不是花钱：调整目标进度不得写入账本，否则预算和报表会把攒钱算成支出。
    func testAdjustmentsNeverCreateTransactions() throws {
        let context = try makeContext()
        let goal = SavingsGoal(name: "应急金", targetAmount: 1_000)
        context.insert(goal)
        try context.save()

        let service = SavingsGoalService(modelContext: context)
        try service.deposit(500, into: goal)
        try service.withdraw(200, from: goal)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CashPoolState>()), 0)
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema(versionedSchema: FlashCountSchemaV3.self),
            configurations: configuration
        )
        return ModelContext(container)
    }
}
