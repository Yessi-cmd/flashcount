import SwiftData
import XCTest
@testable import FlashCount

/// 补账时的「关联到已有交易」以及旧数据的发生项回填。
///
/// `link` 存在的理由很实际：用户常常已经手工记过那笔房租，这时再生成一笔就是
/// 重复记账。所以关联必须只登记发生项、不写新交易、不动资金池。
@MainActor
final class RecurringBackfillLinkTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    /// 关联既有交易：不新增交易、不改资金池，但发生项要落成 linked 并推进游标。
    func testLinkingRecordsOccurrenceWithoutCreatingATransaction() throws {
        let context = try makeContext()
        let category = Category(name: "固定服务", icon: "repeat", colorHex: "#123456")
        context.insert(category)
        context.insert(CashPoolState(transactionDelta: 0))

        let due = date(2026, 3, 10)
        let rule = RecurringRule(
            title: "房租",
            amount: 3_000,
            frequency: .monthly,
            nextDueDate: due,
            category: category
        )
        context.insert(rule)

        // 用户自己已经记过这笔房租
        let manual = Transaction(
            amount: 3_000,
            isExpense: true,
            note: "手工记的房租",
            date: due,
            cashPoolDelta: -3_000,
            category: category
        )
        context.insert(manual)
        try context.save()

        let service = RecurringOccurrenceService(modelContext: context, calendar: calendar)
        let previews = service.pendingOccurrences(rules: [rule], occurrences: [], now: date(2026, 3, 15))
        let preview = try XCTUnwrap(previews.first)

        let transactionCountBefore = try context.fetchCount(FetchDescriptor<Transaction>())
        let result = try service.resolve(
            [
                RecurringBackfillSelection(
                    occurrenceKey: preview.id,
                    action: .link,
                    transactionID: manual.id
                )
            ],
            now: date(2026, 3, 15)
        )

        XCTAssertEqual(result.linkedCount, 1)
        XCTAssertEqual(result.generatedCount, 0)
        XCTAssertEqual(result.cashPoolDelta, 0, "关联不该再动资金池——那笔钱早就记过了")
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<Transaction>()),
            transactionCountBefore,
            "关联不得新增交易，否则就是重复记账"
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CashPoolState>()).first?.transactionDelta,
            0
        )

        let occurrence = try XCTUnwrap(context.fetch(FetchDescriptor<RecurringOccurrence>()).first)
        XCTAssertEqual(occurrence.status, .linked)
        XCTAssertEqual(occurrence.transactionID, manual.id)
        XCTAssertEqual(occurrence.amount, 3_000)
        XCTAssertGreaterThan(rule.nextDueDate, due, "已解决的到期日应推进游标")
    }

    /// 关联到一个不存在的交易 ID 时应整条跳过，而不是留下悬空的发生项。
    func testLinkingToAMissingTransactionIsIgnored() throws {
        let context = try makeContext()
        let rule = RecurringRule(
            title: "宽带",
            amount: 100,
            frequency: .monthly,
            nextDueDate: date(2026, 3, 10)
        )
        context.insert(rule)
        try context.save()

        let service = RecurringOccurrenceService(modelContext: context, calendar: calendar)
        let preview = try XCTUnwrap(
            service.pendingOccurrences(rules: [rule], occurrences: [], now: date(2026, 3, 15)).first
        )

        let result = try service.resolve(
            [
                RecurringBackfillSelection(
                    occurrenceKey: preview.id,
                    action: .link,
                    transactionID: UUID()
                )
            ],
            now: date(2026, 3, 15)
        )

        XCTAssertEqual(result.linkedCount, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RecurringOccurrence>()), 0, "不该留下悬空发生项")
    }

    /// 补账可以顺手改写金额与备注——实际扣款常与规则登记的不一致。
    func testGeneratingWithOverriddenAmountAndNote() throws {
        let context = try makeContext()
        context.insert(CashPoolState(transactionDelta: 0))
        let rule = RecurringRule(
            title: "水电",
            amount: 200,
            frequency: .monthly,
            nextDueDate: date(2026, 3, 10)
        )
        context.insert(rule)
        try context.save()

        let service = RecurringOccurrenceService(modelContext: context, calendar: calendar)
        let preview = try XCTUnwrap(
            service.pendingOccurrences(rules: [rule], occurrences: [], now: date(2026, 3, 15)).first
        )

        let result = try service.resolve(
            [
                RecurringBackfillSelection(
                    occurrenceKey: preview.id,
                    action: .generate,
                    amount: 265,
                    note: "这个月用得多"
                )
            ],
            now: date(2026, 3, 15)
        )

        XCTAssertEqual(result.generatedCount, 1)
        XCTAssertEqual(result.cashPoolDelta, -265, "资金池按实际金额变动")
        let created = try XCTUnwrap(context.fetch(FetchDescriptor<Transaction>()).first)
        XCTAssertEqual(created.amount, 265)
        XCTAssertEqual(created.note, "这个月用得多")
        XCTAssertEqual(created.recurringRule?.id, rule.id, "补出来的交易要挂回规则")
    }

    // MARK: - 旧数据回填

    /// 老版本只写交易、没有发生项记录。回填要为它们补上，且必须幂等。
    func testReconcileLegacyOccurrencesIsIdempotent() throws {
        let context = try makeContext()
        let rule = RecurringRule(
            title: "房租",
            amount: 3_000,
            frequency: .monthly,
            nextDueDate: date(2026, 4, 10)
        )
        context.insert(rule)
        let legacy = Transaction(
            amount: 3_000,
            isExpense: true,
            note: "旧版生成的房租",
            date: date(2026, 3, 10),
            recurringRule: rule
        )
        context.insert(legacy)
        // 没有规则来源的普通交易不该被回填
        context.insert(Transaction(amount: 15, note: "买咖啡", date: date(2026, 3, 11)))
        try context.save()

        let service = RecurringOccurrenceService(modelContext: context, calendar: calendar)
        try service.reconcileLegacyOccurrences()
        try context.save()

        let afterFirst = try context.fetch(FetchDescriptor<RecurringOccurrence>())
        XCTAssertEqual(afterFirst.count, 1, "只为有规则来源的交易补发生项")
        let occurrence = try XCTUnwrap(afterFirst.first)
        XCTAssertEqual(occurrence.status, .generated)
        XCTAssertEqual(occurrence.transactionID, legacy.id)
        XCTAssertEqual(occurrence.amount, 3_000)

        try service.reconcileLegacyOccurrences()
        try context.save()
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<RecurringOccurrence>()),
            1,
            "重复回填不能产生第二条"
        )
    }

    // MARK: - 夹具

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
