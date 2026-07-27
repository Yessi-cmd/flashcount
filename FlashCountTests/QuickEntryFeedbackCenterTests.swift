import SwiftData
import SwiftUI
import XCTest
@testable import FlashCount

/// 保存后的提示条是「撤销刚记的一笔」唯一入口，所以它的生命周期要确定：
/// 出现、被新的一笔顶掉、手动收起、以及自己过期。
@MainActor
final class QuickEntryFeedbackCenterTests: XCTestCase {
    func testPresentPublishesEntryAndDismissClearsIt() throws {
        let center = QuickEntryFeedbackCenter()
        let entry = try makeEntry(amount: 25, isExpense: true, categoryName: "餐饮 · 咖啡")

        XCTAssertNil(center.lastSaved)

        center.present(entry)
        XCTAssertEqual(center.lastSaved?.id, entry.id)

        center.dismiss()
        XCTAssertNil(center.lastSaved, "手动收起后不应残留可撤销状态")
    }

    /// 连续记两笔时，提示条必须指向后一笔——否则撤销会删掉用户没在看的那条记录。
    func testPresentingASecondEntryReplacesTheFirst() throws {
        let center = QuickEntryFeedbackCenter()
        let first = try makeEntry(amount: 10, isExpense: true, categoryName: "餐饮")
        let second = try makeEntry(amount: 20, isExpense: true, categoryName: "出行")

        center.present(first)
        center.present(second)

        XCTAssertEqual(center.lastSaved?.id, second.id)
        XCTAssertEqual(center.lastSaved?.amount, 20)
    }

    func testEntryExpiresOnItsOwn() async throws {
        let center = QuickEntryFeedbackCenter(visibleDuration: .milliseconds(60))
        center.present(try makeEntry(amount: 5, isExpense: true, categoryName: "餐饮"))
        XCTAssertNotNil(center.lastSaved)

        try await Task.sleep(for: .milliseconds(400))

        XCTAssertNil(center.lastSaved, "提示条是撤销的时间窗，不该常驻")
    }

    /// 被顶掉的第一笔不能带着自己的过期计时继续跑，否则它会把后一笔一起清掉。
    func testReplacedEntrysExpiryDoesNotCancelTheNewOne() async throws {
        let center = QuickEntryFeedbackCenter(visibleDuration: .milliseconds(200))
        center.present(try makeEntry(amount: 1, isExpense: true, categoryName: "餐饮"))
        try await Task.sleep(for: .milliseconds(120))

        let second = try makeEntry(amount: 2, isExpense: true, categoryName: "出行")
        center.present(second)
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(center.lastSaved?.id, second.id, "第一笔的计时不应带走第二笔")
    }

    // MARK: - 文案

    func testHeadlineDistinguishesExpenseFromIncome() throws {
        let expense = try makeEntry(amount: 25, isExpense: true, categoryName: "餐饮")
        let income = try makeEntry(amount: 25, isExpense: false, categoryName: "工资")

        XCTAssertTrue(expense.headline.hasPrefix("已记支出"), expense.headline)
        XCTAssertTrue(income.headline.hasPrefix("已记收入"), income.headline)
        XCTAssertTrue(expense.headline.contains(Decimal(25).formattedCurrency))
    }

    /// 补录日期只在不是今天时出现——每笔都写一遍「今天」等于没写。
    func testDetailAppendsBackdatedTextOnlyWhenPresent() throws {
        let today = try makeEntry(amount: 1, isExpense: true, categoryName: "餐饮")
        XCTAssertEqual(today.detail, "餐饮")

        let backdated = try makeEntry(
            amount: 1,
            isExpense: true,
            categoryName: "餐饮",
            backdatedText: "补录 7月24日"
        )
        XCTAssertEqual(backdated.detail, "餐饮 · 补录 7月24日")
    }

    // MARK: - 夹具

    private func makeEntry(
        amount: Decimal,
        isExpense: Bool,
        categoryName: String,
        backdatedText: String? = nil
    ) throws -> QuickEntryFeedbackCenter.SavedEntry {
        QuickEntryFeedbackCenter.SavedEntry(
            transactionID: try makePersistentID(),
            amount: amount,
            isExpense: isExpense,
            categoryName: categoryName,
            backdatedText: backdatedText
        )
    }

    /// 提示条按 ID 取回交易而不是持有对象，所以夹具也得给一个真实的
    /// `PersistentIdentifier`——insert 之后必须 save 才会有稳定 ID。
    private func makePersistentID() throws -> PersistentIdentifier {
        let container = try ModelContainer(
            for: Schema(versionedSchema: FlashCountSchemaV3.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let transaction = Transaction(amount: 1, note: "fixture")
        context.insert(transaction)
        try context.save()
        return transaction.persistentModelID
    }
}

/// 三联指标的横纵排规则。定成 `dynamicTypeSize` 判断而不是 `ViewThatFits`
/// 是有原因的（见类型注释），这条测试就是防止有人改回去。
final class AdaptiveMetricLayoutTests: XCTestCase {
    func testStaysHorizontalUpToTheLargestNonAccessibilitySize() {
        for size in [DynamicTypeSize.xSmall, .medium, .large, .xLarge, .xxLarge, .xxxLarge] {
            XCTAssertTrue(
                AdaptiveMetricLayout.isHorizontal(for: size),
                "\(size) 仍应横排：等宽三联在这些字号下放得下"
            )
        }
    }

    func testFallsBackToVerticalAtAccessibilitySizes() {
        for size in [
            DynamicTypeSize.accessibility1,
            .accessibility2,
            .accessibility3,
            .accessibility4,
            .accessibility5
        ] {
            XCTAssertFalse(
                AdaptiveMetricLayout.isHorizontal(for: size),
                "\(size) 必须纵排：横排会把金额压到看不清而不是换行"
            )
        }
    }
}
