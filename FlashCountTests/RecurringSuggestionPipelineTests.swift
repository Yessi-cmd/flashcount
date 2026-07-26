import SwiftData
import XCTest
@testable import FlashCount

/// 周期建议的后台管线：`@ModelActor` 读快照 → actor 计算。
///
/// 这条路和主线程直接调用 `RecurringSuggestionService` 必须给出同一个结果，
/// 否则界面上看到的建议取决于它是从哪条路算出来的。快照是值类型也是硬要求——
/// SwiftData 模型不 `Sendable`，带过去就会在主线程之外触碰上下文。
final class RecurringSuggestionPipelineTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    /// 数据存取器只读支出交易，并把关联的分类/账本/规则压成 ID。
    @MainActor
    func testDataStoreSnapshotsExpensesWithFlattenedRelationships() async throws {
        let context = try makeContext()
        let category = Category(name: "固定服务", icon: "repeat", colorHex: "#123456")
        let ledger = Ledger.defaultLedgers()[0]
        context.insert(category)
        context.insert(ledger)

        let expense = Transaction(
            amount: 30,
            isExpense: true,
            note: "视频会员",
            date: date(2026, 3, 10),
            category: category,
            ledger: ledger
        )
        context.insert(expense)
        // 收入不参与周期建议——建议的目的是发现固定支出。
        context.insert(Transaction(amount: 9_000, isExpense: false, note: "工资", date: date(2026, 3, 10)))
        context.insert(
            RecurringRule(title: "已有规则", amount: 30, frequency: .monthly, nextDueDate: date(2026, 4, 10), category: category)
        )
        try context.save()

        let input = try await RecurringSuggestionDataStore(modelContainer: context.container).makeInput()

        XCTAssertEqual(input.transactions.count, 1, "只读支出")
        let snapshot = try XCTUnwrap(input.transactions.first)
        XCTAssertEqual(snapshot.amount, 30)
        XCTAssertEqual(snapshot.note, "视频会员")
        XCTAssertEqual(snapshot.categoryID, category.id)
        XCTAssertEqual(snapshot.categoryName, "固定服务")
        XCTAssertEqual(snapshot.categoryIsArchived, false)
        XCTAssertEqual(snapshot.ledgerID, ledger.id)
        XCTAssertNil(snapshot.recurringRuleID, "手工记的账没有规则来源")

        XCTAssertEqual(input.existingRules.count, 1)
        XCTAssertEqual(input.existingRules.first?.frequency, .monthly)
        XCTAssertEqual(input.existingRules.first?.categoryID, category.id)
    }

    /// 后台管线与主线程直算必须得到同一批建议。
    @MainActor
    func testPipelineResultMatchesDirectCalculation() async throws {
        let context = try makeContext()
        let category = Category(name: "固定服务", icon: "repeat", colorHex: "#123456")
        context.insert(category)
        for month in 1...3 {
            context.insert(Transaction(
                amount: 30,
                isExpense: true,
                note: "视频会员",
                date: date(2026, month, 10),
                category: category
            ))
        }
        try context.save()
        let reference = date(2026, 4, 5)

        let input = try await RecurringSuggestionDataStore(modelContainer: context.container).makeInput()
        let viaPipeline = await RecurringSuggestionWorker().calculate(
            input: input,
            dismissedFingerprints: [],
            referenceDate: reference,
            calendar: calendar
        )
        let direct = RecurringSuggestionService.suggestions(
            input: input,
            dismissedFingerprints: [],
            referenceDate: reference,
            calendar: calendar
        )

        XCTAssertEqual(viaPipeline.count, 1)
        XCTAssertEqual(viaPipeline.map(\.fingerprint), direct.map(\.fingerprint))
        XCTAssertEqual(viaPipeline.first?.frequency, .monthly)
        XCTAssertEqual(viaPipeline.first?.amount, 30)
    }

    /// 忽略过的建议在后台这条路上同样要被过滤掉。
    @MainActor
    func testPipelineRespectsDismissedFingerprints() async throws {
        let context = try makeContext()
        let category = Category(name: "固定服务", icon: "repeat", colorHex: "#123456")
        context.insert(category)
        for month in 1...3 {
            context.insert(Transaction(
                amount: 30,
                isExpense: true,
                note: "视频会员",
                date: date(2026, month, 10),
                category: category
            ))
        }
        try context.save()
        let reference = date(2026, 4, 5)

        let input = try await RecurringSuggestionDataStore(modelContainer: context.container).makeInput()
        let worker = RecurringSuggestionWorker()
        let all = await worker.calculate(
            input: input,
            dismissedFingerprints: [],
            referenceDate: reference,
            calendar: calendar
        )
        let fingerprint = try XCTUnwrap(all.first?.fingerprint)

        let filtered = await worker.calculate(
            input: input,
            dismissedFingerprints: [fingerprint],
            referenceDate: reference,
            calendar: calendar
        )
        XCTAssertTrue(filtered.isEmpty)
    }

    @MainActor
    func testEmptyStoreProducesNoSuggestions() async throws {
        let context = try makeContext()
        let input = try await RecurringSuggestionDataStore(modelContainer: context.container).makeInput()

        XCTAssertTrue(input.transactions.isEmpty)
        XCTAssertTrue(input.existingRules.isEmpty)

        let suggestions = await RecurringSuggestionWorker().calculate(
            input: input,
            dismissedFingerprints: [],
            referenceDate: date(2026, 4, 5),
            calendar: calendar
        )
        XCTAssertTrue(suggestions.isEmpty)
    }

    // MARK: - 夹具

    @MainActor
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(versionedSchema: FlashCountSchemaV3.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}
