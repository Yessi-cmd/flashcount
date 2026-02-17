import Foundation
import SwiftData

/// 资产类型
enum AssetType: String, Codable, CaseIterable {
    case bankCard = "银行卡"
    case cash = "现金"
    case investment = "理财"
    case creditCard = "信用卡"
    case loan = "贷款"
    case onlinePay = "网络账户"    // 支付宝/微信余额等
    case other = "其他"

    var icon: String {
        switch self {
        case .bankCard: return "creditcard.fill"
        case .cash: return "banknote.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .creditCard: return "creditcard.trianglebadge.exclamationmark.fill"
        case .loan: return "building.columns.fill"
        case .onlinePay: return "iphone.gen3"
        case .other: return "ellipsis.circle.fill"
        }
    }

    /// 是否为负债类型
    var isLiability: Bool {
        switch self {
        case .creditCard, .loan: return true
        default: return false
        }
    }
}

/// 资产/负债账户
@Model
final class Asset {
    var id: UUID
    var name: String           // "招商银行储蓄卡" / "花呗" / "理财通"
    var type: AssetType
    var balance: Decimal       // 余额 (正数；负债用 type 区分)
    var icon: String           // 自定义 SF Symbol
    var colorHex: String
    var note: String
    var isArchived: Bool
    var updatedAt: Date
    var createdAt: Date

    /// 签名余额：资产为正，负债为负
    var signedBalance: Decimal {
        type.isLiability ? -balance : balance
    }

    init(
        name: String,
        type: AssetType,
        balance: Decimal,
        icon: String? = nil,
        colorHex: String = "#667EEA",
        note: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.balance = balance
        self.icon = icon ?? type.icon
        self.colorHex = colorHex
        self.note = note
        self.isArchived = false
        self.updatedAt = Date()
        self.createdAt = Date()
    }
}
