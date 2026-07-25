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
