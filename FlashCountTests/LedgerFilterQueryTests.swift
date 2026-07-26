import SwiftData
import XCTest
@testable import FlashCount

/// 账本筛选与排序。
///
/// 关键不变量：数据库层的排序（`FetchDescriptor.sortBy`）和后置筛选后的
/// 内存排序必须给出同一个顺序。两者一旦不一致，翻页时条目会在页之间跳动、
/// 重复出现或干脆漏掉——而这只在同时用了分类/搜索筛选时才暴露。
@MainActor
final class LedgerFilterQueryTests: XCTestCase {
    // MARK: - 排序

    func testAllFourSortCombinationsOrderAsExpected() throws {
        let context = try makeContext()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // 金额与日期刻意反向排列，这样两种排序字段会给出不同结果。
        for (offset, amount) in [(0, 30), (1, 20), (2, 10)] {
            context.insert(Transaction(
                amount: Decimal(amount),
                note: "第\(offset)笔",
                date: base.addingTimeInterval(TimeInterval(offset * 86_400))
            ))
        }
        try context.save()
        let service = LedgerQueryService(modelContext: context)

        let expectations: [(TransactionSortField, TransactionSortDirection, [Decimal])] = [
            (.date, .ascending, [30, 20, 10]),
            (.date, .descending, [10, 20, 30]),
            (.amount, .ascending, [10, 20, 30]),
            (.amount, .descending, [30, 20, 10])
        ]

        for (field, direction, expected) in expectations {
            let page = try service.fetchPage(
                filter: makeFilter(sortField: field, sortDirection: direction),
                offset: 0,
                limit: 50
            )
            XCTAssertEqual(page.transactions.map(\.amount), expected, "\(field.rawValue) \(direction.rawValue) 顺序不符")
        }
    }

    /// 加上需要后置筛选的条件后，顺序必须与不加时一致。
    func testPostFilteredOrderMatchesDatabaseOrder() throws {
        let context = try makeContext()
        let category = Category(name: "餐饮", icon: "fork.knife", colorHex: "#FF7A70")
        context.insert(category)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<12 {
            context.insert(Transaction(
                amount: Decimal((index * 7) % 13 + 1),
                note: "关键词\(index)",
                date: base.addingTimeInterval(TimeInterval(index * 3_600)),
                category: category
            ))
        }
        try context.save()
        let service = LedgerQueryService(modelContext: context)

        for field in [TransactionSortField.date, .amount] {
            for direction in [TransactionSortDirection.ascending, .descending] {
                let plain = try service.fetchPage(
                    filter: makeFilter(sortField: field, sortDirection: direction),
                    offset: 0,
                    limit: 50
                )
                let postFiltered = try service.fetchPage(
                    filter: makeFilter(searchText: "关键词", sortField: field, sortDirection: direction),
                    offset: 0,
                    limit: 50
                )
                XCTAssertEqual(
                    postFiltered.transactions.map(\.id),
                    plain.transactions.map(\.id),
                    "\(field.rawValue)/\(direction.rawValue)：后置筛选的顺序必须与数据库排序一致，否则翻页会跳条目"
                )
            }
        }
    }

    // MARK: - 金额与类型筛选

    func testAmountRangeIsInclusiveOnBothEnds() throws {
        let context = try makeContext()
        for amount in [5, 10, 15, 20, 25] {
            context.insert(Transaction(amount: Decimal(amount)))
        }
        try context.save()
        let service = LedgerQueryService(modelContext: context)

        let page = try service.fetchPage(
            filter: makeFilter(minAmount: 10, maxAmount: 20),
            offset: 0,
            limit: 50
        )
        XCTAssertEqual(Set(page.transactions.map(\.amount)), [10, 15, 20], "上下界都应包含")

        let onlyMin = try service.fetchPage(filter: makeFilter(minAmount: 20), offset: 0, limit: 50)
        XCTAssertEqual(Set(onlyMin.transactions.map(\.amount)), [20, 25])

        let onlyMax = try service.fetchPage(filter: makeFilter(maxAmount: 10), offset: 0, limit: 50)
        XCTAssertEqual(Set(onlyMax.transactions.map(\.amount)), [5, 10])
    }

    func testExpenseFilterSelectsOneSideOnly() throws {
        let context = try makeContext()
        context.insert(Transaction(amount: 10, isExpense: true))
        context.insert(Transaction(amount: 20, isExpense: false))
        try context.save()
        let service = LedgerQueryService(modelContext: context)

        let expenses = try service.fetchPage(filter: makeFilter(isExpense: true), offset: 0, limit: 50)
        XCTAssertEqual(expenses.transactions.map(\.amount), [10])

        let incomes = try service.fetchPage(filter: makeFilter(isExpense: false), offset: 0, limit: 50)
        XCTAssertEqual(incomes.transactions.map(\.amount), [20])

        XCTAssertEqual(try service.fetchCount(filter: makeFilter()), 2, "不带类型筛选时两边都算")
    }

    /// 日期区间是 `[start, end)`：起点当天要算进来，终点当天不算。
    func testDateRangeIncludesStartAndExcludesEnd() throws {
        let context = try makeContext()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(86_400)
        context.insert(Transaction(amount: 1, note: "起点", date: start))
        context.insert(Transaction(amount: 2, note: "区间内", date: start.addingTimeInterval(3_600)))
        context.insert(Transaction(amount: 3, note: "终点", date: end))
        try context.save()

        let page = try LedgerQueryService(modelContext: context).fetchPage(
            filter: makeFilter(startDate: start, endDate: end),
            offset: 0,
            limit: 50
        )
        XCTAssertEqual(Set(page.transactions.map(\.note)), ["起点", "区间内"])
    }

    // MARK: - 分类筛选

    /// 按一级分类筛选必须把子分类的交易一起带上——报表卡片就是按一级分类聚合的，
    /// 下钻只列直接挂在一级分类上的那些会让明细对不上总数。
    func testRootCategoryFilterIncludesChildTransactions() throws {
        let context = try makeContext()
        let root = Category(name: "餐饮", icon: "fork.knife", colorHex: "#FF7A70")
        let child = Category(
            name: "外卖",
            icon: "takeoutbag.and.cup.and.straw.fill",
            colorHex: "#FF9F43",
            parentCategoryName: "餐饮"
        )
        let unrelated = Category(name: "出行", icon: "bus.fill", colorHex: "#45C4B0")
        [root, child, unrelated].forEach(context.insert)
        context.insert(Transaction(amount: 10, note: "挂一级", category: root))
        context.insert(Transaction(amount: 20, note: "挂子类", category: child))
        context.insert(Transaction(amount: 30, note: "别的组", category: unrelated))
        try context.save()

        let service = LedgerQueryService(modelContext: context)
        let page = try service.fetchPage(filter: makeFilter(categoryRootName: "餐饮"), offset: 0, limit: 50)

        XCTAssertEqual(Set(page.transactions.map(\.note)), ["挂一级", "挂子类"])
        XCTAssertEqual(try service.summary(filter: makeFilter(categoryRootName: "餐饮")).expense, 30)
    }

    func testCategoryIDFilterMatchesThatCategoryOnly() throws {
        let context = try makeContext()
        let root = Category(name: "餐饮", icon: "fork.knife", colorHex: "#FF7A70")
        let child = Category(name: "外卖", icon: "bag", colorHex: "#FF9F43", parentCategoryName: "餐饮")
        [root, child].forEach(context.insert)
        context.insert(Transaction(amount: 10, note: "挂一级", category: root))
        context.insert(Transaction(amount: 20, note: "挂子类", category: child))
        try context.save()

        let page = try LedgerQueryService(modelContext: context).fetchPage(
            filter: makeFilter(categoryID: child.id),
            offset: 0,
            limit: 50
        )
        XCTAssertEqual(page.transactions.map(\.note), ["挂子类"], "按具体分类筛选时不应连带同组的其他分类")
    }

    /// 汇总与列表必须基于同一套筛选结果，否则顶部合计和下面的列表对不上。
    func testSummaryMatchesTheFilteredList() throws {
        let context = try makeContext()
        context.insert(Transaction(amount: 10, isExpense: true, note: "含关键词 A"))
        context.insert(Transaction(amount: 25, isExpense: true, note: "含关键词 B"))
        context.insert(Transaction(amount: 100, isExpense: false, note: "含关键词 C"))
        context.insert(Transaction(amount: 999, isExpense: true, note: "无关"))
        try context.save()

        let filter = makeFilter(searchText: "关键词")
        let service = LedgerQueryService(modelContext: context)
        let page = try service.fetchPage(filter: filter, offset: 0, limit: 50)
        let summary = try service.summary(filter: filter)

        XCTAssertEqual(page.transactions.count, 3)
        XCTAssertEqual(summary.expense, 35, "10 + 25")
        XCTAssertEqual(summary.income, 100)
        XCTAssertEqual(try service.fetchMatchingIDs(filter: filter).count, 3)
    }

    // MARK: - 夹具

    private func makeFilter(
        startDate: Date? = nil,
        endDate: Date? = nil,
        isExpense: Bool? = nil,
        categoryID: UUID? = nil,
        categoryRootName: String? = nil,
        minAmount: Decimal? = nil,
        maxAmount: Decimal? = nil,
        searchText: String? = nil,
        sortField: TransactionSortField = .date,
        sortDirection: TransactionSortDirection = .descending
    ) -> LedgerFilter {
        LedgerFilter(
            startDate: startDate,
            endDate: endDate,
            isExpense: isExpense,
            categoryID: categoryID,
            categoryRootName: categoryRootName,
            minAmount: minAmount,
            maxAmount: maxAmount,
            searchText: searchText,
            includeProtectedIncomeMetadata: true,
            sortField: sortField,
            sortDirection: sortDirection
        )
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(versionedSchema: FlashCountSchemaV3.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}
