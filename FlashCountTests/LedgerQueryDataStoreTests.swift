import SwiftData
import XCTest
@testable import FlashCount

/// 账本查询的后台 `@ModelActor` 入口。
///
/// 它和主线程的 `LedgerQueryService` 是同一套筛选逻辑的两个出口，结果必须一致——
/// 账本页顶部的合计走后台、列表走主线程，两边不一致就会出现「合计和列表对不上」。
/// 后台只把持久化引用带回主线程，不跨 actor 携带模型对象。
final class LedgerQueryDataStoreTests: XCTestCase {
    @MainActor
    func testBackgroundSummaryMatchesMainThreadSummary() async throws {
        let context = try makeContext()
        context.insert(Transaction(amount: 30, isExpense: true, note: "含关键词 A"))
        context.insert(Transaction(amount: 12, isExpense: true, note: "含关键词 B"))
        context.insert(Transaction(amount: 500, isExpense: false, note: "含关键词 C"))
        context.insert(Transaction(amount: 999, isExpense: true, note: "无关"))
        try context.save()

        let filter = makeFilter(searchText: "关键词")
        let onMain = try LedgerQueryService(modelContext: context).summary(filter: filter)
        let inBackground = try await LedgerQueryDataStore(modelContainer: context.container).summary(filter: filter)

        XCTAssertEqual(inBackground.expense, onMain.expense)
        XCTAssertEqual(inBackground.income, onMain.income)
        XCTAssertEqual(inBackground.hasHiddenIncome, onMain.hasHiddenIncome)
        XCTAssertEqual(inBackground.expense, 42, "30 + 12，不含被筛掉的 999")
        XCTAssertEqual(inBackground.income, 500)
    }

    @MainActor
    func testBackgroundMatchingIDsMatchMainThread() async throws {
        let context = try makeContext()
        let category = Category(name: "餐饮", icon: "fork.knife", colorHex: "#FF7A70")
        let child = Category(name: "外卖", icon: "bag", colorHex: "#FF9F43", parentCategoryName: "餐饮")
        context.insert(category)
        context.insert(child)
        context.insert(Transaction(amount: 10, note: "挂一级", category: category))
        context.insert(Transaction(amount: 20, note: "挂子类", category: child))
        context.insert(Transaction(amount: 30, note: "无分类"))
        try context.save()

        let filter = makeFilter(categoryRootName: "餐饮")
        let onMain = try LedgerQueryService(modelContext: context).fetchMatchingIDs(filter: filter)
        let inBackground = try await LedgerQueryDataStore(modelContainer: context.container)
            .fetchMatchingTransactionIDs(filter: filter)

        XCTAssertEqual(inBackground, onMain)
        XCTAssertEqual(inBackground.count, 2, "一级分类筛选要带上子分类的交易")
    }

    /// 需要后置筛选时也必须只返回当前页，而不是把全部匹配项带回主线程。
    @MainActor
    func testPostFilteredPageIsStillLimitedToOnePage() async throws {
        let context = try makeContext()
        for index in 0..<250 {
            context.insert(Transaction(amount: Decimal(index + 1), note: "关键词\(index)"))
        }
        try context.save()

        let store = LedgerQueryDataStore(modelContainer: context.container)
        let filter = makeFilter(searchText: "关键词")
        let first = try await store.fetchPage(filter: filter, offset: 0, limit: 100)
        let second = try await store.fetchPage(filter: filter, offset: 100, limit: 100)

        XCTAssertEqual(first.persistentIDs.count, 100)
        XCTAssertEqual(first.totalCount, 250)
        XCTAssertTrue(first.hasMore)
        XCTAssertEqual(second.offset, 100)
        XCTAssertTrue(
            Set(first.transactionIDs).isDisjoint(with: Set(second.transactionIDs)),
            "相邻页不该有重复条目"
        )
    }

    /// 越界的 offset 与 limit 要被夹到安全值，而不是抛错或返回负数页。
    @MainActor
    func testOutOfRangeOffsetAndLimitAreClamped() async throws {
        let context = try makeContext()
        context.insert(Transaction(amount: 10))
        try context.save()

        let store = LedgerQueryDataStore(modelContainer: context.container)
        let negative = try await store.fetchPage(filter: makeFilter(), offset: -50, limit: 0)
        XCTAssertEqual(negative.offset, 0)
        XCTAssertEqual(negative.persistentIDs.count, 1, "limit 至少为 1")

        let beyondEnd = try await store.fetchPage(filter: makeFilter(), offset: 500, limit: 10)
        XCTAssertTrue(beyondEnd.persistentIDs.isEmpty)
        XCTAssertFalse(beyondEnd.hasMore)
    }

    // MARK: - 夹具

    private func makeFilter(
        categoryRootName: String? = nil,
        searchText: String? = nil
    ) -> LedgerFilter {
        LedgerFilter(
            startDate: nil,
            endDate: nil,
            isExpense: nil,
            categoryID: nil,
            categoryRootName: categoryRootName,
            minAmount: nil,
            maxAmount: nil,
            searchText: searchText,
            includeProtectedIncomeMetadata: true,
            sortField: .date,
            sortDirection: .descending
        )
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(versionedSchema: FlashCountSchemaV3.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}
