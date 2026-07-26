import Foundation

/// 记账页金额输入的纯逻辑：键盘按键如何改写显示串，以及「+」累加之后保存时
/// 到底该用哪个数。
///
/// 抽成独立类型是为了让位数限制和金额累加能被单测——这两段此前埋在
/// `QuickEntryView` 的扩展里、依赖 `@State`，只能靠 UI 测试间接摸到，
/// 而 AGENTS.md 把 `Decimal` 金额正确性列为关键约定。
struct QuickEntryAmountInput: Equatable {
    /// 最大整数位数（万亿级别）。
    static let maxIntegerDigits = 12
    /// 人民币记到分，多余的位数直接不接受。
    static let maxFractionDigits = 2

    /// 显示区当前的输入串。保持字符串而不是 `Decimal`，因为「12.」「0.5」这类
    /// 中间状态是合法的输入过程，转成数字就丢了。
    private(set) var text = ""

    /// 「+」已经折进来的部分。
    private(set) var pendingSum: Decimal = 0

    var hasPendingSum: Bool { pendingSum > 0 }

    /// 两者都空才算没填。
    var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingSum > 0
    }

    /// 保存时的合计预览。当前输入解析不出来就只显示已累加部分。
    var accumulatedPreview: Decimal {
        switch resolved() {
        case .success(let value): return value
        case .failure: return pendingSum
        }
    }

    // MARK: - 按键

    /// 一次金额相关按键的结果。收支切换不经过这里。
    enum KeyOutcome: Equatable {
        /// 内容有变化。`accumulated` 为真时表示刚刚发生了一次「+」累加。
        case changed(accumulated: Bool)
        /// 按键被忽略（超出位数限制、退格到空等），不该报错也不该有反馈。
        case ignored
        /// 需要展示给用户的校验错误。
        case rejected(MoneyValidationError)
    }

    @discardableResult
    mutating func apply(_ key: String) -> KeyOutcome {
        switch key {
        case "⌫":
            guard !text.isEmpty else { return .ignored }
            text.removeLast()
            return .changed(accumulated: false)
        case ".":
            guard !text.contains(".") else { return .ignored }
            text += text.isEmpty ? "0." : "."
            return .changed(accumulated: false)
        case "00":
            return applyDoubleZero()
        case "+":
            return accumulate()
        default:
            return applyDigit(key)
        }
    }

    private mutating func applyDoubleZero() -> KeyOutcome {
        guard integerDigitCount < Self.maxIntegerDigits else { return .ignored }
        if !text.isEmpty && !text.contains(".") {
            text += "00"
            return .changed(accumulated: false)
        }
        if text.contains(".") {
            guard fractionDigitCount < Self.maxFractionDigits else { return .ignored }
            // 小数位只剩一位空间时补一个 0，补两个会溢出到第三位。
            text += fractionDigitCount + 2 <= Self.maxFractionDigits ? "00" : "0"
            return .changed(accumulated: false)
        }
        return .ignored
    }

    private mutating func applyDigit(_ key: String) -> KeyOutcome {
        if text.contains(".") {
            guard fractionDigitCount < Self.maxFractionDigits else { return .ignored }
        } else {
            guard integerDigitCount < Self.maxIntegerDigits else { return .ignored }
        }
        text += key
        return .changed(accumulated: false)
    }

    /// 「+」把当前输入折进累加值，显示区随即清零等下一笔。
    private mutating func accumulate() -> KeyOutcome {
        switch MoneyValidation.parse(text, requirement: .positive) {
        case .success(let value):
            pendingSum += value
            text = ""
            return .changed(accumulated: true)
        case .failure(let error):
            // 已有累加值时空按一下「+」无意义但无害，不该报错。
            if hasPendingSum && text.isEmpty { return .ignored }
            return .rejected(error)
        }
    }

    // MARK: - 整体改写

    /// 套用模板：直接给定金额，并丢掉累加中的部分。
    mutating func replace(with amount: Decimal) {
        text = String(describing: amount)
        pendingSum = 0
    }

    mutating func clearPendingSum() {
        pendingSum = 0
    }

    mutating func reset() {
        text = ""
        pendingSum = 0
    }

    /// 保存用的金额 = 已累加部分 + 当前输入。
    func resolved() -> Result<Decimal, MoneyValidationError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return pendingSum > 0 ? .success(pendingSum) : .failure(.empty)
        }
        switch MoneyValidation.parse(trimmed, requirement: .positive) {
        case .success(let value):
            return .success(pendingSum + value)
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - 位数

    private var integerDigitCount: Int {
        (text.split(separator: ".").first.map(String.init) ?? text).count
    }

    private var fractionDigitCount: Int {
        let parts = text.split(separator: ".")
        return parts.count >= 2 ? parts[1].count : 0
    }
}
