import Foundation
import SwiftData

enum CashPoolItemKind: String, Codable, CaseIterable, Identifiable {
    case cash = "现金/银行卡"
    case flexibleInvestment = "可动用理财"
    case liability = "待还款/分期"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cash: return "现金/银行卡"
        case .flexibleInvestment: return "可动用理财"
        case .liability: return "其他待还款"
        }
    }

    var inputPlaceholder: String {
        switch self {
        case .cash: return "名称，例如：现金/银行卡合计"
        case .flexibleInvestment: return "名称，例如：可随时赎回理财"
        case .liability: return "名称，例如：信用卡待还/朋友借款"
        }
    }

    var icon: String {
        switch self {
        case .cash: return "banknote.fill"
        case .flexibleInvestment: return "chart.line.uptrend.xyaxis"
        case .liability: return "creditcard.trianglebadge.exclamationmark.fill"
        }
    }

    var isNegative: Bool {
        self == .liability
    }
}

@Model
final class CashPoolItem {
    var id: UUID
    var name: String
    var kind: CashPoolItemKind
    var amount: Decimal
    var note: String
    var isArchived: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    var signedAmount: Decimal {
        kind.isNegative ? -amount : amount
    }

    init(
        name: String,
        kind: CashPoolItemKind,
        amount: Decimal,
        note: String = "",
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.kind = kind
        self.amount = amount
        self.note = note
        self.isArchived = false
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class CashPoolState {
    var id: UUID
    var transactionDelta: Decimal
    var updatedAt: Date

    init(transactionDelta: Decimal = 0) {
        self.id = UUID()
        self.transactionDelta = transactionDelta
        self.updatedAt = Date()
    }
}
