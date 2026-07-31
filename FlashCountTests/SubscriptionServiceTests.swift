import XCTest
import SwiftData
@testable import FlashCount

/// 订阅服务：聚合（先乘后除）、增改归档、续费推进。
///
/// 钱正确性：年度等价只做整数乘法（12/4/1），月度合计 = 年度合计 ÷ 12
/// 只除这一次。逐项除再求和会放大舍入，且每月/每年显示会不一致。
@MainActor
final class SubscriptionServiceTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        // 模型与服务的续费推进默认用 Calendar.current；测试期望值必须与之同日历，
        // 否则在不同时区的机器上会因为 00:00 偏移而对不上。
        calendar = Calendar.current
    }

    func testAggregationComputesExactYearlyAndMonthlyTotals() throws {
        let context = try makeContext()
        try insertSubscription(context, name: "月订阅", cost: 10, cycle: .monthly)
        try insertSubscription(context, name: "季订阅", cost: 30, cycle: .quarterly)
        try insertSubscription(context, name: "年订阅", cost: 120, cycle: .yearly)

        let aggregation = SubscriptionAggregation(subscriptions: try context.fetch(FetchDescriptor<Subscription>()))

        XCTAssertEqual(aggregation.count, 3)
        XCTAssertEqual(aggregation.yearlyTotal, 360, "10×12 + 30×4 + 120×1")
        XCTAssertEqual(aggregation.monthlyTotal, 30, "360 ÷ 12，全库只除这一次")
    }

    func testAggregationMultipliesBeforeDividing() throws {
        let context = try makeContext()
        try insertSubscription(context, name: "iCloud", cost: Decimal(string: "9.99")!, cycle: .monthly)

        let aggregation = SubscriptionAggregation(subscriptions: try context.fetch(FetchDescriptor<Subscription>()))

        XCTAssertEqual(aggregation.yearlyTotal, Decimal(string: "119.88")!, "9.99 × 12 精确无舍入")
        XCTAssertEqual(aggregation.monthlyTotal, Decimal(string: "9.99")!)
    }

    func testAggregationPicksEarliestActiveRenewalAndExcludesArchived() throws {
        let context = try makeContext()
        let later = try date(2026, 8, 15)
        let earlier = try date(2026, 7, 10)
        let archived = try insertSubscription(context, name: "已归档", cost: 5, cycle: .monthly, nextDate: try date(2026, 6, 1))
        archived.isArchived = true
        try context.save()
        try insertSubscription(context, name: "稍后", cost: 10, cycle: .monthly, nextDate: later)
        try insertSubscription(context, name: "更早", cost: 15, cycle: .monthly, nextDate: earlier)

        let aggregation = SubscriptionAggregation(subscriptions: try context.fetch(FetchDescriptor<Subscription>()))

        XCTAssertEqual(aggregation.count, 2, "归档订阅不进聚合")
        XCTAssertEqual(aggregation.nextRenewalDate, earlier)
        XCTAssertEqual(aggregation.nextRenewalName, "更早")
    }

    func testAdvanceRenewalWritesExpenseAndAdvancesDate() throws {
        let context = try makeContext()
        context.insert(CashPoolItem(name: "现金", kind: .cash, amount: 1_000))
        context.insert(Ledger(name: "默认账本", icon: "book", colorHex: "#000000", isDefault: true))
        let subscription = try insertSubscription(
            context,
            name: "Netflix",
            cost: 10,
            cycle: .monthly,
            nextDate: try date(2026, 7, 31)
        )

        let before = try availableAmount(in: context)
        let transaction = try SubscriptionService(modelContext: context)
            .advanceRenewal(subscription, draft: .init(date: try date(2026, 7, 31)))

        let created = try XCTUnwrap(transaction, "默认应生成对应的支出交易")
        XCTAssertTrue(created.isExpense)
        XCTAssertEqual(created.amount, 10)
        XCTAssertEqual(created.note, "Netflix 续费")
        XCTAssertEqual(created.cashPoolDelta, -10)
        XCTAssertEqual(created.ledger?.isDefault, true)
        XCTAssertEqual(subscription.nextRenewalDate, try date(2026, 8, 31), "月订阅推进一个月")

        let after = try availableAmount(in: context)
        XCTAssertEqual(after, before - 10, "续费是真实支出，可动用资金应减少恰好一期的钱")
    }

    func testAdvanceRenewalWithoutTransactionOnlyAdvancesDate() throws {
        let context = try makeContext()
        context.insert(CashPoolItem(name: "现金", kind: .cash, amount: 1_000))
        let subscription = try insertSubscription(
            context,
            name: "Spotify",
            cost: 10,
            cycle: .monthly,
            nextDate: try date(2026, 7, 15)
        )

        let before = try availableAmount(in: context)
        let transaction = try SubscriptionService(modelContext: context)
            .advanceRenewal(subscription, draft: .init(recordsTransaction: false))

        XCTAssertNil(transaction)
        XCTAssertEqual(subscription.nextRenewalDate, try date(2026, 8, 15))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 0)
        XCTAssertEqual(try availableAmount(in: context), before, "仅推进日期时资金不动")
    }

    func testProjectedRenewalDateClampsShortMonthsWithoutDrift() throws {
        let context = try makeContext()
        let subscription = try insertSubscription(
            context,
            name: "会员",
            cost: 10,
            cycle: .monthly,
            nextDate: try date(2026, 1, 31)
        )

        XCTAssertEqual(subscription.renewalDay, 31, "日锚点取自首期日期")
        XCTAssertEqual(subscription.projectedRenewalDate(calendar: calendar), try date(2026, 2, 28), "短月临时夹到月末")

        subscription.nextRenewalDate = try date(2026, 2, 28)
        XCTAssertEqual(subscription.projectedRenewalDate(calendar: calendar), try date(2026, 3, 31), "回到锚日，不漂移")
    }

    func testAddRejectsNonPositiveCostAndEmptyName() throws {
        let context = try makeContext()
        let service = SubscriptionService(modelContext: context)

        XCTAssertThrowsError(
            try service.add(.init(name: "免费", cost: 0, billingCycle: .monthly, nextRenewalDate: Date()))
        ) { error in
            guard case SubscriptionService.SubscriptionError.invalidCost = error else {
                return XCTFail("应拒绝非正金额，实际错误：\(error)")
            }
        }
        XCTAssertThrowsError(
            try service.add(.init(name: "  ", cost: 10, billingCycle: .monthly, nextRenewalDate: Date()))
        ) { error in
            guard case SubscriptionService.SubscriptionError.invalidName = error else {
                return XCTFail("应拒绝空名称，实际错误：\(error)")
            }
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Subscription>()), 0)
    }

    func testArchiveExcludesFromAggregationAndSnapshot() throws {
        let context = try makeContext()
        let service = SubscriptionService(modelContext: context)
        let subscription = try service.add(
            .init(name: "iCloud", cost: 6, billingCycle: .monthly, nextRenewalDate: Date())
        )

        let before = SubscriptionAggregation(subscriptions: try context.fetch(FetchDescriptor<Subscription>()))
        XCTAssertEqual(before.count, 1)
        XCTAssertTrue(
            SubscriptionRenewalSnapshotStore().load().contains { $0.id == subscription.id },
            "新增订阅后快照应包含它"
        )

        try service.archive(subscription)

        let after = SubscriptionAggregation(subscriptions: try context.fetch(FetchDescriptor<Subscription>()))
        XCTAssertEqual(after.count, 0, "归档订阅不进聚合")
        XCTAssertFalse(
            SubscriptionRenewalSnapshotStore().load().contains { $0.id == subscription.id },
            "归档后快照应剔除它"
        )
    }

    // MARK: - 工具

    private func insertSubscription(
        _ context: ModelContext,
        name: String,
        cost: Decimal,
        cycle: SubscriptionBillingCycle,
        nextDate: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) throws -> Subscription {
        let subscription = Subscription(
            name: name,
            cost: cost,
            billingCycle: cycle,
            nextRenewalDate: nextDate
        )
        context.insert(subscription)
        try context.save()
        return subscription
    }

    private func availableAmount(in context: ModelContext) throws -> Decimal {
        let service = CashPoolService(modelContext: context)
        let items = try context.fetch(FetchDescriptor<CashPoolItem>())
        return service.availableAmount(items: items, state: try service.state())
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema(versionedSchema: FlashCountSchemaV4.self),
            configurations: configuration
        )
        return ModelContext(container)
    }
}

/// 快照 store：调度镜像的读写与归档过滤。
final class SubscriptionRenewalSnapshotStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        suiteName = "SubscriptionSnapshotTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testLoadWithMissingKeyReturnsEmpty() {
        let store = SubscriptionRenewalSnapshotStore(userDefaults: defaults)
        XCTAssertEqual(store.load(), [])
    }

    func testSaveAndLoadRoundTrip() throws {
        let item = SubscriptionRenewalItem(
            id: UUID(),
            name: "iCloud",
            nextRenewalDate: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 15))),
            remindBeforeDays: 3
        )
        let store = SubscriptionRenewalSnapshotStore(userDefaults: defaults)
        store.save([item])

        XCTAssertEqual(store.load(), [item], "ISO8601 日期与字段应精确往返")
    }

    func testRefreshFiltersArchived() throws {
        let active = Subscription(
            name: "Netflix",
            cost: 10,
            billingCycle: .monthly,
            nextRenewalDate: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        )
        let archived = Subscription(
            name: "旧会员",
            cost: 5,
            billingCycle: .yearly,
            nextRenewalDate: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        )
        archived.isArchived = true

        let items = SubscriptionRenewalSnapshotStore.refresh(
            from: [active, archived],
            userDefaults: defaults
        )

        XCTAssertEqual(items.map(\.id), [active.id])
        XCTAssertEqual(SubscriptionRenewalSnapshotStore(userDefaults: defaults).load().map(\.id), [active.id])
    }
}
