import Foundation
import SwiftData

/// 记账模板 — 一键填入金额 / 分类 / 备注
@Model
final class TransactionTemplate {
    var id: UUID
    var name: String           // 模板显示名称，如"早餐"
    var amount: Decimal        // 金额（始终为正数）
    var isExpense: Bool        // true=支出, false=收入
    var note: String           // 预设备注（可空）
    var categoryName: String?  // 关联的分类名称（运行时查找 Category）
    var sortOrder: Int

    init(
        name: String,
        amount: Decimal,
        isExpense: Bool = true,
        note: String = "",
        categoryName: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.amount = amount
        self.isExpense = isExpense
        self.note = note
        self.categoryName = categoryName
        self.sortOrder = sortOrder
    }

    /// 预设默认模板
    static func defaultTemplates() -> [TransactionTemplate] {
        [
            TransactionTemplate(
                name: "公交",
                amount: 1.6,
                note: "",
                categoryName: "公交地铁",
                sortOrder: 0
            ),
            TransactionTemplate(
                name: "早餐",
                amount: 6,
                note: "",
                categoryName: "早餐",
                sortOrder: 1
            ),
            TransactionTemplate(
                name: "咖啡",
                amount: 9.9,
                note: "",
                categoryName: "咖啡",
                sortOrder: 2
            ),
        ]
    }
}
