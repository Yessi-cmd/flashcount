import Foundation

enum MoneyValidation {
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
