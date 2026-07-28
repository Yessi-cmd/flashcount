import Foundation
import SwiftData

/// 资金项的种类。`isNegative` 决定它在净资产里是加项还是减项——
/// 「待还款/分期」是唯一的负向种类。
///
/// SwiftData raw value 保持兼容；备份使用独立的稳定 key，避免用户文案变化
/// 破坏旧备份的可读性。面向用户的文案走 `displayName`。
enum CashPoolItemKind: String, Codable, CaseIterable, Identifiable {
    case cash = "现金/银行卡"
    case flexibleInvestment = "可动用理财"
    case liability = "待还款/分期"

    var id: String { rawValue }

    /// Stable key for backups. Keep the SwiftData raw values unchanged for
    /// schema compatibility, but never make backup compatibility depend on
    /// user-facing Chinese copy.
    var backupKey: String {
        switch self {
        case .cash: return "cash"
        case .flexibleInvestment: return "flexibleInvestment"
        case .liability: return "liability"
        }
    }

    static func fromBackupKey(_ rawValue: String) -> Self? {
        switch rawValue {
        case "cash", "现金/银行卡": return .cash
        case "flexibleInvestment", "可动用理财": return .flexibleInvestment
        case "liability", "待还款/分期": return .liability
        default: return nil
        }
    }

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

/// 手工登记的一笔资金（现金、可赎回理财、待还款）。
///
/// 资金池是净资产的唯一真源，这些条目加总即「资金净额」。
/// 实物资产与储蓄目标刻意不在其中：前者不易变现，后者的钱本就还在资金里。
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

/// 资金池里由记账累计出来的增减（`transactionDelta`）。
///
/// 全库只应有一条：多条会让余额来源变得不确定，`DataHealthService` 因此
/// 把重复状态列为可修复问题，只保留最近更新的那条。这个数字是用户唯一
/// 无从自行核对的分量，所以资产页要能下钻到它背后的交易。
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
