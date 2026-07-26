import Foundation
import SwiftData

/// 历史「账户」类型。账户体系已于 2026-07 移除，此枚举仅用于解析旧数据。
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

/// 历史「账户」模型 — 已停用。
///
/// 账户体系与资金池语义重叠（两者都在记「我有多少钱」），却被净资产直接相加，
/// 同一张银行卡两边都记就会双计；而且它从来没有新建入口，余额也不随记账变动。
/// 2026-07 决定移除，改由资金池单一口径承担。
///
/// 这个类只为两件事保留：让 `FlashCountSchemaV1/V2` 仍能编译，
/// 以及让 V2→V3 迁移能读出旧账户并折算成资金项。**不要在新代码里使用它。**
@Model
final class Asset {
    var id: UUID
    var name: String
    var type: AssetType
    var balance: Decimal
    var icon: String
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
        self.balance = max(balance, 0)
        self.icon = icon ?? type.icon
        self.colorHex = colorHex
        self.note = note
        self.isArchived = false
        self.updatedAt = Date()
        self.createdAt = Date()
    }
}

/// 旧账户 → 资金项的折算规则。
/// 迁移旧数据库和导入旧备份都走这里，保证两条路径口径一致。
enum LegacyAssetConversion {
    /// 负债类账户折成「待还款」，理财折成「可动用理财」，其余都归入「现金/银行卡」。
    static func cashPoolKind(forAssetType rawType: String) -> CashPoolItemKind {
        guard let type = AssetType(rawValue: rawType) else { return .cash }
        if type.isLiability { return .liability }
        return type == .investment ? .flexibleInvestment : .cash
    }

    /// 折算后的备注保留原账户类型，避免「银行卡 / 网络账户」这类信息在合并后丢失。
    static func note(forAssetType rawType: String, existingNote: String) -> String {
        let origin = "原账户类型：\(rawType)"
        let trimmed = existingNote.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? origin : "\(origin) · \(trimmed)"
    }

    static func makeCashPoolItem(
        name: String,
        rawType: String,
        balance: Decimal,
        existingNote: String,
        isArchived: Bool,
        createdAt: Date,
        updatedAt: Date,
        sortOrder: Int
    ) -> CashPoolItem {
        let item = CashPoolItem(
            name: name,
            kind: cashPoolKind(forAssetType: rawType),
            amount: max(balance, 0),
            note: note(forAssetType: rawType, existingNote: existingNote),
            sortOrder: sortOrder
        )
        item.isArchived = isArchived
        item.createdAt = createdAt
        item.updatedAt = updatedAt
        return item
    }
}
