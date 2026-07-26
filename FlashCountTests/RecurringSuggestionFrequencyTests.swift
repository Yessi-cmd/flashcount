import XCTest
@testable import FlashCount

/// 周期建议里日频与年频的识别，以及「太久没发生就别再建议」的时效规则。
///
/// 现有的 `RecurringSuggestionServiceTests` 覆盖月频与周频；这两档的最小次数
/// 和时效阈值都不同，各自单独判断，漏测就会出现「一年前的年费还在建议」
/// 或「连续几天买咖啡被当成固定账单」这类误报。
@MainActor
final class RecurringSuggestionFrequencyTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    // MARK: - 日频

    /// 日频要求至少 5 次连续。
    func testDailyPatternNeedsFiveConsecutiveDays() throws {
        let category = Category(name: "固定服务", icon: "repeat", colorHex: "#123456")

        let fourDays = (10...13).map { day in
            transaction(on: (2026, 3, day), amount: 8, note: "通勤地铁", category: category)
        }
        XCTAssertTrue(
            suggestions(fourDays, reference: date(2026, 3, 14)).isEmpty,
            "只有 4 天不足以判定为日频"
        )

        let fiveDays = (10...14).map { day in
            transaction(on: (2026, 3, day), amount: 8, note: "通勤地铁", category: category)
        }
        let suggestion = try XCTUnwrap(suggestions(fiveDays, reference: date(2026, 3, 15)).first)
        XCTAssertEqual(suggestion.frequency, .daily)
        XCTAssertEqual(suggestion.occurrenceCount, 5)
        XCTAssertTrue(calendar.isDate(suggestion.nextDueDate, inSameDayAs: date(2026, 3, 15)))
    }

    /// 日频断一天就不算连续。
    func testDailyPatternIsBrokenByAMissingDay() {
        let category = Category(name: "固定服务", icon: "repeat", colorHex: "#123456")
        let withGap = [10, 11, 12, 14, 15].map { day in
            transaction(on: (2026, 3, day), amount: 8, note: "通勤地铁", category: category)
        }
        XCTAssertTrue(suggestions(withGap, reference: date(2026, 3, 16)).isEmpty)
    }

    /// 日频超过 3 天没发生就不再建议——它本该每天出现。
    func testStaleDailyPatternIsNotSuggested() {
        let category = Category(name: "固定服务", icon: "repeat", colorHex: "#123456")
        let daily = (10...14).map { day in
            transaction(on: (2026, 3, day), amount: 8, note: "通勤地铁", category: category)
        }

        XCTAssertFalse(suggestions(daily, reference: date(2026, 3, 17)).isEmpty, "停 3 天仍在容忍范围内")
        XCTAssertTrue(suggestions(daily, reference: date(2026, 3, 20)).isEmpty, "停 6 天就不该再建议")
    }

    // MARK: - 年频

    /// 年频只需 2 次，但必须同月且日位置对得上。
    func testYearlyPatternNeedsOnlyTwoOccurrences() throws {
        let category = Category(name: "固定服务", icon: "repeat", colorHex: "#123456")
        let twoYears = [
            transaction(on: (2025, 6, 18), amount: 588, note: "云盘年费", category: category),
            transaction(on: (2026, 6, 18), amount: 588, note: "云盘年费", category: category)
        ]

        let suggestion = try XCTUnwrap(suggestions(twoYears, reference: date(2026, 7, 1)).first)
        XCTAssertEqual(suggestion.frequency, .yearly)
        XCTAssertEqual(suggestion.occurrenceCount, 2)
        XCTAssertEqual(suggestion.amount, 588)
        XCTAssertTrue(calendar.isDate(suggestion.nextDueDate, inSameDayAs: date(2027, 6, 18)))
    }

    func testYearlyPatternRejectsDifferentMonths() {
        let category = Category(name: "固定服务", icon: "repeat", colorHex: "#123456")
        let differentMonths = [
            transaction(on: (2025, 6, 18), amount: 588, note: "云盘年费", category: category),
            transaction(on: (2026, 8, 18), amount: 588, note: "云盘年费", category: category)
        ]
        XCTAssertTrue(suggestions(differentMonths, reference: date(2026, 9, 1)).isEmpty)
    }

    func testYearlyPatternRejectsNonConsecutiveYears() {
        let category = Category(name: "固定服务", icon: "repeat", colorHex: "#123456")
        let skippedYear = [
            transaction(on: (2024, 6, 18), amount: 588, note: "云盘年费", category: category),
            transaction(on: (2026, 6, 18), amount: 588, note: "云盘年费", category: category)
        ]
        XCTAssertTrue(suggestions(skippedYear, reference: date(2026, 7, 1)).isEmpty, "隔了一年不算连续")
    }

    /// 年费超过 2 年没再出现就别建议了——很可能已经不续订了。
    func testStaleYearlyPatternIsNotSuggested() {
        let category = Category(name: "固定服务", icon: "repeat", colorHex: "#123456")
        let yearly = [
            transaction(on: (2022, 6, 18), amount: 588, note: "云盘年费", category: category),
            transaction(on: (2023, 6, 18), amount: 588, note: "云盘年费", category: category)
        ]
        XCTAssertTrue(suggestions(yearly, reference: date(2026, 7, 1)).isEmpty)
    }

    /// 月末对齐同样适用于年频：2 月末与 2 月末算同一个日位置。
    func testYearlyMonthEndAlignmentMatchesAcrossLeapYears() throws {
        let category = Category(name: "固定服务", icon: "repeat", colorHex: "#123456")
        let monthEnds = [
            transaction(on: (2024, 2, 29), amount: 100, note: "年检", category: category),
            transaction(on: (2025, 2, 28), amount: 100, note: "年检", category: category)
        ]

        let suggestion = try XCTUnwrap(suggestions(monthEnds, reference: date(2025, 3, 5)).first)
        XCTAssertEqual(suggestion.frequency, .yearly)
        XCTAssertTrue(
            calendar.isDate(suggestion.nextDueDate, inSameDayAs: date(2026, 2, 28)),
            "下一次应落在 2026 年 2 月末"
        )
    }

    // MARK: - 时效（周频与月频）

    func testStaleWeeklyAndMonthlyPatternsAreNotSuggested() {
        let category = Category(name: "固定服务", icon: "repeat", colorHex: "#123456")

        let weekly = [
            transaction(on: (2026, 1, 5), amount: 60, note: "周会咖啡", category: category),
            transaction(on: (2026, 1, 12), amount: 60, note: "周会咖啡", category: category),
            transaction(on: (2026, 1, 19), amount: 60, note: "周会咖啡", category: category)
        ]
        XCTAssertFalse(suggestions(weekly, reference: date(2026, 2, 5)).isEmpty, "停 17 天仍在 21 天容忍内")
        XCTAssertTrue(suggestions(weekly, reference: date(2026, 3, 5)).isEmpty, "停一个多月就不该再建议")

        let monthly = [
            transaction(on: (2025, 9, 10), amount: 300, note: "宽带", category: category),
            transaction(on: (2025, 10, 10), amount: 300, note: "宽带", category: category),
            transaction(on: (2025, 11, 10), amount: 300, note: "宽带", category: category)
        ]
        XCTAssertFalse(suggestions(monthly, reference: date(2026, 1, 5)).isEmpty, "隔 2 个月仍在 3 个月容忍内")
        XCTAssertTrue(suggestions(monthly, reference: date(2026, 6, 5)).isEmpty, "隔半年就不该再建议")
    }

    /// 未来日期的记录不参与判定——否则补录一笔未来的账会凭空造出建议。
    func testOccurrencesAfterTheReferenceDateAreIgnored() {
        let category = Category(name: "固定服务", icon: "repeat", colorHex: "#123456")
        let futureRun = (10...14).map { day in
            transaction(on: (2026, 3, day), amount: 8, note: "通勤地铁", category: category)
        }
        XCTAssertTrue(
            suggestions(futureRun, reference: date(2026, 3, 1)).isEmpty,
            "参照日之前还没发生的记录不该被当成已成型的规律"
        )
    }

    // MARK: - 夹具

    private func suggestions(_ transactions: [Transaction], reference: Date) -> [RecurringSuggestion] {
        RecurringSuggestionService.suggestions(
            transactions: transactions,
            existingRules: [],
            referenceDate: reference,
            calendar: calendar
        )
    }

    private func transaction(
        on components: (Int, Int, Int),
        amount: Decimal,
        note: String,
        category: FlashCount.Category
    ) -> Transaction {
        Transaction(
            amount: amount,
            note: note,
            date: date(components.0, components.1, components.2),
            category: category
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}
