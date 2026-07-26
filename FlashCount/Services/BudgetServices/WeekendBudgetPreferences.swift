import Foundation

/// 用户可以选择的周末额度权重。
enum WeekendBudgetMultiplier: Int, CaseIterable, Identifiable {
    case oneAndHalf = 150
    case double = 200

    var id: Int { rawValue }

    var decimalValue: Decimal {
        Decimal(rawValue) / Decimal(100)
    }

    var title: String {
        "\(displayValue) 倍"
    }

    private var displayValue: String {
        switch self {
        case .oneAndHalf: return "1.5"
        case .double: return "2"
        }
    }
}

/// 周末额度倍数的读写与归一化，存在 `@AppStorage`。
///
/// 存的是百分比整数（150 / 200）而不是 `Decimal`，因为 `@AppStorage`
/// 不直接支持 `Decimal`；任何非法值一律回落到默认档，避免存进一个
/// 会让每日额度算出离谱结果的倍数。周末提高的额度会由工作日自动摊平，
/// 整个发薪周期的预算上限不变。
enum WeekendBudgetPreferences {
    static let storageKey = "weekendBudgetMultiplierPercent"
    static let defaultRawValue = WeekendBudgetMultiplier.oneAndHalf.rawValue

    static func normalizedRawValue(_ rawValue: Int) -> Int {
        WeekendBudgetMultiplier(rawValue: rawValue)?.rawValue ?? defaultRawValue
    }

    static func multiplier(for rawValue: Int) -> Decimal {
        WeekendBudgetMultiplier(rawValue: normalizedRawValue(rawValue))?.decimalValue
            ?? WeekendBudgetMultiplier.oneAndHalf.decimalValue
    }

    static func option(for rawValue: Int) -> WeekendBudgetMultiplier {
        WeekendBudgetMultiplier(rawValue: normalizedRawValue(rawValue)) ?? .oneAndHalf
    }
}
