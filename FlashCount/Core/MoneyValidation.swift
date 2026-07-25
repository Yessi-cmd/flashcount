import Foundation

enum MoneyValidationRequirement {
    case positive
    case nonNegative
}

enum MoneyValidationError: Equatable, LocalizedError {
    case empty
    case invalidFormat
    case mustBePositive
    case mustBeNonNegative

    var errorDescription: String? {
        switch self {
        case .empty:
            return "请输入金额"
        case .invalidFormat:
            return "请输入有效金额，例如 12.50"
        case .mustBePositive:
            return "金额必须大于 0"
        case .mustBeNonNegative:
            return "金额不能小于 0"
        }
    }
}

enum MoneyValidation {
    static func parse(
        _ rawValue: String,
        requirement: MoneyValidationRequirement
    ) -> Result<Decimal, MoneyValidationError> {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        // Decimal(string:) accepts formats such as exponent notation. Amount
        // fields use a decimal keypad, so keep the accepted grammar explicit:
        // digits with at most one decimal point. A leading dot is normalized
        // for text fields that do not use QuickEntry's keypad.
        var normalized = trimmed
        if normalized.hasPrefix("-.") {
            normalized = "-0\(normalized.dropFirst())"
        } else if normalized.hasPrefix(".") {
            normalized = "0\(normalized)"
        }
        let grammarValue = normalized.hasPrefix("-") ? String(normalized.dropFirst()) : normalized
        let scalarValues = grammarValue.unicodeScalars.map(\.value)
        let decimalPointCount = scalarValues.count(where: { $0 == 46 })
        guard !grammarValue.isEmpty,
              decimalPointCount <= 1,
              !grammarValue.hasSuffix("."),
              scalarValues.allSatisfy({ (48...57).contains($0) || $0 == 46 }),
              let value = Decimal(string: normalized),
              !value.isNaN else {
            return .failure(.invalidFormat)
        }

        switch requirement {
        case .positive:
            guard value > 0 else { return .failure(.mustBePositive) }
        case .nonNegative:
            guard value >= 0 else { return .failure(.mustBeNonNegative) }
        }
        return .success(value)
    }

    static func nonNegative(_ value: Decimal) -> Bool {
        !value.isNaN && value >= 0
    }

    static func positive(_ value: Decimal) -> Bool {
        !value.isNaN && value > 0
    }

    static func validPhysicalAsset(purchasePrice: Decimal, salvageValue: Decimal, targetDailyCost: Decimal) -> Bool {
        positive(purchasePrice)
            && nonNegative(salvageValue)
            && salvageValue <= purchasePrice
            && positive(targetDailyCost)
    }
}
