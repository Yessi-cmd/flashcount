import Foundation
import SwiftData

/// 交易分类（餐饮、交通、房租等）
@Model
final class Category {
    var id: UUID
    var name: String
    var icon: String          // SF Symbol name
    var colorHex: String      // Hex color string
    var isExpense: Bool       // true = 支出分类, false = 收入分类
    var sortOrder: Int
    var isArchived: Bool

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction] = []

    @Relationship(deleteRule: .nullify, inverse: \RecurringRule.category)
    var recurringRules: [RecurringRule] = []

    init(
        name: String,
        icon: String,
        colorHex: String,
        isExpense: Bool = true,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.isExpense = isExpense
        self.sortOrder = sortOrder
        self.isArchived = false
    }

    // MARK: - 默认分类

    static func defaultExpenseCategories() -> [Category] {
        [
            Category(name: "餐饮", icon: "fork.knife", colorHex: "#FF6B6B", sortOrder: 0),
            Category(name: "交通", icon: "car.fill", colorHex: "#4ECDC4", sortOrder: 1),
            Category(name: "购物", icon: "bag.fill", colorHex: "#FFE66D", sortOrder: 2),
            Category(name: "居住", icon: "house.fill", colorHex: "#A8E6CF", sortOrder: 3),
            Category(name: "娱乐", icon: "gamecontroller.fill", colorHex: "#FF8A5C", sortOrder: 4),
            Category(name: "医疗", icon: "cross.case.fill", colorHex: "#F78FB3", sortOrder: 5),
            Category(name: "教育", icon: "book.fill", colorHex: "#778BEB", sortOrder: 6),
            Category(name: "通讯", icon: "phone.fill", colorHex: "#70A1FF", sortOrder: 7),
            Category(name: "订阅", icon: "repeat", colorHex: "#7BED9F", sortOrder: 8),
            Category(name: "其他", icon: "ellipsis.circle.fill", colorHex: "#B2BEC3", sortOrder: 9),
        ]
    }

    static func defaultIncomeCategories() -> [Category] {
        [
            Category(name: "工资", icon: "briefcase.fill", colorHex: "#2ED573", isExpense: false, sortOrder: 0),
            Category(name: "奖金", icon: "star.fill", colorHex: "#FFD700", isExpense: false, sortOrder: 1),
            Category(name: "投资", icon: "chart.line.uptrend.xyaxis", colorHex: "#1E90FF", isExpense: false, sortOrder: 2),
            Category(name: "兼职", icon: "wrench.and.screwdriver.fill", colorHex: "#FF6348", isExpense: false, sortOrder: 3),
            Category(name: "其他收入", icon: "plus.circle.fill", colorHex: "#A4B0BE", isExpense: false, sortOrder: 4),
        ]
    }
}
