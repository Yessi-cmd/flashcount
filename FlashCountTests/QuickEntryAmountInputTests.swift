import XCTest
@testable import FlashCount

/// 记账键盘的输入规则与「+」累加。
///
/// 这段逻辑此前埋在 `QuickEntryView` 的扩展里、依赖 `@State`，只能靠 UI 测试
/// 间接摸到一两个点，而它正是 AGENTS.md 列为关键约定的 `Decimal` 金额处理。
final class QuickEntryAmountInputTests: XCTestCase {
    // MARK: - 基本输入

    func testDigitsAppendInOrder() {
        var input = QuickEntryAmountInput()
        type("123", into: &input)
        XCTAssertEqual(input.text, "123")
    }

    func testLeadingDecimalSeparatorGetsAZeroInFront() {
        var input = QuickEntryAmountInput()
        input.apply(".")
        XCTAssertEqual(input.text, "0.", "直接按小数点应补出 0.，否则 .5 不是合法金额串")
    }

    func testSecondDecimalSeparatorIsIgnored() {
        var input = QuickEntryAmountInput()
        type("1.5", into: &input)
        XCTAssertEqual(input.apply("."), .ignored)
        XCTAssertEqual(input.text, "1.5")
    }

    func testBackspaceOnEmptyIsIgnoredRatherThanAnError() {
        var input = QuickEntryAmountInput()
        XCTAssertEqual(input.apply("⌫"), .ignored)
        XCTAssertEqual(input.text, "")
    }

    func testBackspaceRemovesTheLastCharacter() {
        var input = QuickEntryAmountInput()
        type("12.5", into: &input)
        input.apply("⌫")
        XCTAssertEqual(input.text, "12.")
    }

    // MARK: - 位数限制

    func testFractionIsCappedAtTwoDigits() {
        var input = QuickEntryAmountInput()
        type("1.23", into: &input)
        XCTAssertEqual(input.apply("4"), .ignored, "人民币记到分，第三位小数不该被接受")
        XCTAssertEqual(input.text, "1.23")
    }

    func testIntegerPartIsCappedAtTwelveDigits() {
        var input = QuickEntryAmountInput()
        type(String(repeating: "9", count: QuickEntryAmountInput.maxIntegerDigits), into: &input)
        XCTAssertEqual(input.text.count, QuickEntryAmountInput.maxIntegerDigits)
        XCTAssertEqual(input.apply("9"), .ignored)
        XCTAssertEqual(input.text.count, QuickEntryAmountInput.maxIntegerDigits)
    }

    /// 整数位满了仍应允许输入小数——上限是整数位数，不是总长度。
    func testDecimalStillAllowedAfterIntegerCapIsReached() {
        var input = QuickEntryAmountInput()
        type(String(repeating: "9", count: QuickEntryAmountInput.maxIntegerDigits), into: &input)
        input.apply(".")
        input.apply("5")
        XCTAssertEqual(input.text, String(repeating: "9", count: QuickEntryAmountInput.maxIntegerDigits) + ".5")
    }

    // MARK: - 「00」键

    func testDoubleZeroAppendsTwoZerosOnIntegers() {
        var input = QuickEntryAmountInput()
        type("5", into: &input)
        input.apply("00")
        XCTAssertEqual(input.text, "500")
    }

    func testDoubleZeroIsIgnoredOnEmptyInput() {
        var input = QuickEntryAmountInput()
        XCTAssertEqual(input.apply("00"), .ignored, "空输入按 00 会得到无意义的前导零")
        XCTAssertEqual(input.text, "")
    }

    /// 小数位只剩一位空间时，「00」只能补一个 0——补两个会溢出到第三位小数。
    ///
    /// 抽取前这里补的是一个 0（`1.` → `1.0`）。改成按剩余空间补满，是因为键帽
    /// 写着「00」；两种结果解析出的 `Decimal` 完全相同，差别只在显示串。
    func testDoubleZeroRespectsRemainingFractionRoom() throws {
        var input = QuickEntryAmountInput()
        type("1.", into: &input)
        input.apply("00")
        XCTAssertEqual(input.text, "1.00")
        XCTAssertEqual(try input.resolved().get(), 1, "1.0 与 1.00 是同一个金额")

        var oneDigitLeft = QuickEntryAmountInput()
        type("1.5", into: &oneDigitLeft)
        oneDigitLeft.apply("00")
        XCTAssertEqual(oneDigitLeft.text, "1.50", "只剩一位小数空间时只能补一个 0")
        XCTAssertEqual(try oneDigitLeft.resolved().get(), Decimal(string: "1.5"))
    }

    func testDoubleZeroIsIgnoredWhenFractionIsFull() {
        var input = QuickEntryAmountInput()
        type("1.23", into: &input)
        XCTAssertEqual(input.apply("00"), .ignored)
        XCTAssertEqual(input.text, "1.23")
    }

    // MARK: - 累加

    func testAccumulateFoldsCurrentInputAndClearsDisplay() {
        var input = QuickEntryAmountInput()
        type("12.50", into: &input)
        XCTAssertEqual(input.apply("+"), .changed(accumulated: true))

        XCTAssertEqual(input.pendingSum, Decimal(string: "12.50"))
        XCTAssertEqual(input.text, "", "累加后显示区要清空等下一笔")
        XCTAssertTrue(input.canSubmit, "已累加的部分本身就够保存")
    }

    func testResolvedSumsPendingAndCurrentInput() throws {
        var input = QuickEntryAmountInput()
        type("12.50", into: &input)
        input.apply("+")
        type("7.25", into: &input)

        XCTAssertEqual(try input.resolved().get(), Decimal(string: "19.75"))
        XCTAssertEqual(input.accumulatedPreview, Decimal(string: "19.75"))
    }

    func testMultipleAccumulationsAddUp() throws {
        var input = QuickEntryAmountInput()
        for amount in ["1.10", "2.20", "3.30"] {
            type(amount, into: &input)
            input.apply("+")
        }
        XCTAssertEqual(try input.resolved().get(), Decimal(string: "6.60"))
    }

    func testResolvedFallsBackToPendingSumWhenDisplayIsEmpty() throws {
        var input = QuickEntryAmountInput()
        type("30", into: &input)
        input.apply("+")
        XCTAssertEqual(try input.resolved().get(), 30)
    }

    /// 已有累加值时空按「+」无意义但无害，不该弹校验错误。
    func testAccumulatingEmptyInputAfterAPendingSumIsIgnored() {
        var input = QuickEntryAmountInput()
        type("10", into: &input)
        input.apply("+")
        XCTAssertEqual(input.apply("+"), .ignored)
        XCTAssertEqual(input.pendingSum, 10)
    }

    func testAccumulatingEmptyInputWithoutPendingSumReportsError() {
        var input = QuickEntryAmountInput()
        XCTAssertEqual(input.apply("+"), .rejected(.empty))
        XCTAssertEqual(input.pendingSum, 0)
    }

    func testClearPendingSumKeepsCurrentInput() {
        var input = QuickEntryAmountInput()
        type("10", into: &input)
        input.apply("+")
        type("3", into: &input)

        input.clearPendingSum()
        XCTAssertEqual(input.pendingSum, 0)
        XCTAssertEqual(input.text, "3", "清除累加不该连正在输入的数字一起清掉")
    }

    // MARK: - 可提交与整体改写

    func testEmptyInputCannotBeSubmitted() {
        var input = QuickEntryAmountInput()
        XCTAssertFalse(input.canSubmit)
        XCTAssertEqual(input.resolved(), .failure(.empty))

        input.apply("1")
        XCTAssertTrue(input.canSubmit)
    }

    func testZeroIsRejectedBecauseAmountsMustBePositive() {
        var input = QuickEntryAmountInput()
        input.apply("0")
        XCTAssertTrue(input.canSubmit, "输入了内容，按钮可点")
        XCTAssertEqual(input.resolved(), .failure(.mustBePositive), "但 0 元不是一笔账")
    }

    func testReplaceWithTemplateAmountDropsPendingSum() throws {
        var input = QuickEntryAmountInput()
        type("99", into: &input)
        input.apply("+")

        input.replace(with: Decimal(string: "6.5") ?? 6.5)
        XCTAssertEqual(input.pendingSum, 0, "套用模板是重新开始，不该带着上一次的累加")
        XCTAssertEqual(try input.resolved().get(), Decimal(string: "6.5"))
    }

    func testResetClearsEverything() {
        var input = QuickEntryAmountInput()
        type("12", into: &input)
        input.apply("+")
        type("3", into: &input)

        input.reset()
        XCTAssertEqual(input, QuickEntryAmountInput())
        XCTAssertFalse(input.canSubmit)
    }

    // MARK: - 工具

    private func type(_ keys: String, into input: inout QuickEntryAmountInput) {
        for character in keys {
            input.apply(String(character))
        }
    }
}
