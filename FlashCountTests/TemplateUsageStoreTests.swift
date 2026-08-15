import XCTest
@testable import FlashCount

final class TemplateUsageStoreTests: XCTestCase {
    private var suiteName: String {
        "TemplateUsageStoreTests.\(UUID().uuidString)"
    }

    func testPinnedTemplatesKeepManualOrderAndUsedTemplatesMoveForward() {
        let templates = [
            TransactionTemplate(name: "公交", amount: 1.6, sortOrder: 0),
            TransactionTemplate(name: "早餐", amount: 6, sortOrder: 1),
            TransactionTemplate(name: "咖啡", amount: 9.9, sortOrder: 2),
            TransactionTemplate(name: "午餐", amount: 25, sortOrder: 3),
            TransactionTemplate(name: "晚餐", amount: 35, sortOrder: 4),
        ]
        let usage: [UUID: TemplateUsageRecord] = [
            templates[3].id: TemplateUsageRecord(
                useCount: 2,
                lastUsedAt: Date(timeIntervalSince1970: 200)
            ),
            templates[4].id: TemplateUsageRecord(
                useCount: 1,
                lastUsedAt: Date(timeIntervalSince1970: 100)
            ),
        ]

        let ordered = TemplateDisplayOrder.ordered(templates, usage: usage)

        XCTAssertEqual(ordered.map(\.name), ["公交", "早餐", "午餐", "晚餐", "咖啡"])
    }

    func testRecentlyUsedFlexibleTemplateBeatsMoreFrequentOlderOne() {
        let templates = [
            TransactionTemplate(name: "固定一", amount: 1, sortOrder: 0),
            TransactionTemplate(name: "固定二", amount: 2, sortOrder: 1),
            TransactionTemplate(name: "旧但多次", amount: 3, sortOrder: 2),
            TransactionTemplate(name: "新但一次", amount: 4, sortOrder: 3),
        ]
        let usage: [UUID: TemplateUsageRecord] = [
            templates[2].id: TemplateUsageRecord(
                useCount: 10,
                lastUsedAt: Date(timeIntervalSince1970: 100)
            ),
            templates[3].id: TemplateUsageRecord(
                useCount: 1,
                lastUsedAt: Date(timeIntervalSince1970: 200)
            ),
        ]

        let ordered = TemplateDisplayOrder.ordered(templates, usage: usage)

        XCTAssertEqual(ordered.map(\.name), ["固定一", "固定二", "新但一次", "旧但多次"])
    }

    func testStorePersistsUsageCountAndLastUsedDate() throws {
        let suiteName = suiteName
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = TemplateUsageStore(userDefaults: defaults)
        let templateID = UUID()
        let firstUse = Date(timeIntervalSince1970: 100)
        let secondUse = Date(timeIntervalSince1970: 200)

        store.record(templateID, at: firstUse)
        store.record(templateID, at: secondUse)

        let record = try XCTUnwrap(store.load()[templateID])
        XCTAssertEqual(record.useCount, 2)
        XCTAssertEqual(record.lastUsedAt, secondUse)
    }

    func testOrderingFallsBackToManualOrderWithoutUsage() {
        let templates = [
            TransactionTemplate(name: "一", amount: 1, sortOrder: 0),
            TransactionTemplate(name: "二", amount: 2, sortOrder: 1),
            TransactionTemplate(name: "三", amount: 3, sortOrder: 2),
        ]

        let ordered = TemplateDisplayOrder.ordered(templates, usage: [:])

        XCTAssertEqual(ordered.map(\.name), ["一", "二", "三"])
    }
}
