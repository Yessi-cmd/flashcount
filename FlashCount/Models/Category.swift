import Foundation
import SwiftData

struct CategoryItemDefinition: Hashable {
    let name: String
    let icon: String
    let colorHex: String
}

struct CategoryGroupDefinition: Hashable {
    let name: String
    let icon: String
    let colorHex: String
    let children: [CategoryItemDefinition]
}

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
        makeCategories(from: expenseCategoryGroups(), isExpense: true)
    }

    static func defaultIncomeCategories() -> [Category] {
        makeCategories(from: incomeCategoryGroups(), isExpense: false)
    }
}

extension Category {
    static func expenseCategoryGroups() -> [CategoryGroupDefinition] {
        [
            CategoryGroupDefinition(
                name: "餐饮",
                icon: "fork.knife",
                colorHex: "#FF7A70",
                children: [
                    CategoryItemDefinition(name: "正餐", icon: "fork.knife.circle.fill", colorHex: "#FF7A70"),
                    CategoryItemDefinition(name: "外卖", icon: "takeoutbag.and.cup.and.straw.fill", colorHex: "#FF9F43"),
                    CategoryItemDefinition(name: "早餐", icon: "sunrise.fill", colorHex: "#F7B267"),
                    CategoryItemDefinition(name: "奶茶", icon: "takeoutbag.and.cup.and.straw.fill", colorHex: "#D89A5B"),
                    CategoryItemDefinition(name: "咖啡", icon: "cup.and.saucer.fill", colorHex: "#8B5E3C"),
                    CategoryItemDefinition(name: "零食", icon: "birthday.cake.fill", colorHex: "#F6C667"),
                    CategoryItemDefinition(name: "水果", icon: "leaf.fill", colorHex: "#66D37E"),
                    CategoryItemDefinition(name: "饮料", icon: "waterbottle.fill", colorHex: "#5BC0EB"),
                    CategoryItemDefinition(name: "聚餐", icon: "person.2.fill", colorHex: "#FF8FAB"),
                ]
            ),
            CategoryGroupDefinition(
                name: "出行",
                icon: "bus.fill",
                colorHex: "#45C4B0",
                children: [
                    CategoryItemDefinition(name: "公交地铁", icon: "tram.fill", colorHex: "#45C4B0"),
                    CategoryItemDefinition(name: "打车", icon: "car.fill", colorHex: "#4D96FF"),
                    CategoryItemDefinition(name: "共享单车", icon: "bicycle", colorHex: "#2EC4B6"),
                    CategoryItemDefinition(name: "停车过路", icon: "parkingsign.circle.fill", colorHex: "#6C8DFF"),
                    CategoryItemDefinition(name: "加油充电", icon: "fuelpump.fill", colorHex: "#5B8DEF"),
                    CategoryItemDefinition(name: "火车飞机", icon: "airplane.departure", colorHex: "#5BC0EB"),
                ]
            ),
            CategoryGroupDefinition(
                name: "购物",
                icon: "basket.fill",
                colorHex: "#70D6A3",
                children: [
                    CategoryItemDefinition(name: "日用品", icon: "basket.fill", colorHex: "#70D6A3"),
                    CategoryItemDefinition(name: "服饰鞋包", icon: "tshirt.fill", colorHex: "#FF8CC6"),
                    CategoryItemDefinition(name: "美妆个护", icon: "sparkles", colorHex: "#FFB3C6"),
                    CategoryItemDefinition(name: "数码配件", icon: "headphones", colorHex: "#7B8CDE"),
                    CategoryItemDefinition(name: "家具家电", icon: "washer.fill", colorHex: "#8BA7FF"),
                    CategoryItemDefinition(name: "大件消费", icon: "shippingbox.fill", colorHex: "#A3A1FB"),
                ]
            ),
            CategoryGroupDefinition(
                name: "居家",
                icon: "house.fill",
                colorHex: "#8FD6C8",
                children: [
                    CategoryItemDefinition(name: "房租", icon: "key.fill", colorHex: "#8BA7FF"),
                    CategoryItemDefinition(name: "房贷", icon: "building.2.fill", colorHex: "#6C8DFF"),
                    CategoryItemDefinition(name: "水电燃气", icon: "bolt.fill", colorHex: "#FFD166"),
                    CategoryItemDefinition(name: "物业", icon: "door.left.hand.open", colorHex: "#7BDCB5"),
                    CategoryItemDefinition(name: "维修", icon: "wrench.and.screwdriver.fill", colorHex: "#9AA6B2"),
                    CategoryItemDefinition(name: "家政", icon: "spray.fill", colorHex: "#B8E0D2"),
                ]
            ),
            CategoryGroupDefinition(
                name: "固定服务",
                icon: "antenna.radiowaves.left.and.right",
                colorHex: "#74B9FF",
                children: [
                    CategoryItemDefinition(name: "手机话费", icon: "iphone", colorHex: "#74B9FF"),
                    CategoryItemDefinition(name: "宽带网络", icon: "wifi", colorHex: "#45C4B0"),
                    CategoryItemDefinition(name: "视频会员", icon: "play.tv.fill", colorHex: "#B28DFF"),
                    CategoryItemDefinition(name: "音乐会员", icon: "music.note", colorHex: "#FF8FAB"),
                    CategoryItemDefinition(name: "云服务", icon: "icloud.fill", colorHex: "#5BC0EB"),
                    CategoryItemDefinition(name: "软件订阅", icon: "app.badge.fill", colorHex: "#7B8CDE"),
                    CategoryItemDefinition(name: "游戏会员", icon: "gamecontroller.fill", colorHex: "#8E7CFF"),
                    CategoryItemDefinition(name: "其他订阅", icon: "repeat", colorHex: "#66D37E"),
                ]
            ),
            CategoryGroupDefinition(
                name: "娱乐",
                icon: "gamecontroller.fill",
                colorHex: "#B28DFF",
                children: [
                    CategoryItemDefinition(name: "电影演出", icon: "ticket.fill", colorHex: "#B28DFF"),
                    CategoryItemDefinition(name: "游戏", icon: "gamecontroller.fill", colorHex: "#8E7CFF"),
                    CategoryItemDefinition(name: "书影音", icon: "books.vertical.fill", colorHex: "#7B8CDE"),
                    CategoryItemDefinition(name: "运动休闲", icon: "figure.run", colorHex: "#2EC4B6"),
                    CategoryItemDefinition(name: "展览活动", icon: "photo.on.rectangle.angled", colorHex: "#FFB703"),
                ]
            ),
            CategoryGroupDefinition(
                name: "健康",
                icon: "cross.case.fill",
                colorHex: "#FF6F91",
                children: [
                    CategoryItemDefinition(name: "药品", icon: "pills.fill", colorHex: "#FF6F91"),
                    CategoryItemDefinition(name: "门诊", icon: "stethoscope", colorHex: "#F87171"),
                    CategoryItemDefinition(name: "体检", icon: "heart.text.square.fill", colorHex: "#FB7185"),
                    CategoryItemDefinition(name: "牙科", icon: "mouth.fill", colorHex: "#60A5FA"),
                    CategoryItemDefinition(name: "健身", icon: "dumbbell.fill", colorHex: "#2EC4B6"),
                    CategoryItemDefinition(name: "保险", icon: "shield.lefthalf.filled", colorHex: "#45C4B0"),
                ]
            ),
            CategoryGroupDefinition(
                name: "学习",
                icon: "book.fill",
                colorHex: "#4E8CFF",
                children: [
                    CategoryItemDefinition(name: "课程", icon: "graduationcap.fill", colorHex: "#4E8CFF"),
                    CategoryItemDefinition(name: "书籍", icon: "book.fill", colorHex: "#5BC0EB"),
                    CategoryItemDefinition(name: "考试", icon: "checklist.checked", colorHex: "#6C8DFF"),
                    CategoryItemDefinition(name: "软件工具", icon: "hammer.fill", colorHex: "#7B8CDE"),
                    CategoryItemDefinition(name: "文具", icon: "pencil.and.ruler.fill", colorHex: "#F7C948"),
                    CategoryItemDefinition(name: "资料", icon: "doc.text.fill", colorHex: "#74B9FF"),
                ]
            ),
            CategoryGroupDefinition(
                name: "社交",
                icon: "gift.fill",
                colorHex: "#FF8FAB",
                children: [
                    CategoryItemDefinition(name: "请客", icon: "person.2.wave.2.fill", colorHex: "#FF8FAB"),
                    CategoryItemDefinition(name: "人情红包", icon: "envelope.fill", colorHex: "#FF6B88"),
                    CategoryItemDefinition(name: "礼物", icon: "gift.fill", colorHex: "#F472B6"),
                    CategoryItemDefinition(name: "约会", icon: "heart.fill", colorHex: "#F43F5E"),
                    CategoryItemDefinition(name: "同事聚会", icon: "person.3.fill", colorHex: "#A78BFA"),
                    CategoryItemDefinition(name: "家庭活动", icon: "figure.2.and.child.holdinghands", colorHex: "#FB923C"),
                ]
            ),
            CategoryGroupDefinition(
                name: "账务",
                icon: "creditcard.fill",
                colorHex: "#6C8DFF",
                children: [
                    CategoryItemDefinition(name: "转账", icon: "arrow.left.arrow.right", colorHex: "#6C8DFF"),
                    CategoryItemDefinition(name: "手续费", icon: "percent", colorHex: "#9AA6B2"),
                    CategoryItemDefinition(name: "还款", icon: "creditcard.fill", colorHex: "#4D96FF"),
                    CategoryItemDefinition(name: "分期", icon: "calendar.badge.clock", colorHex: "#8BA7FF"),
                    CategoryItemDefinition(name: "利息", icon: "chart.line.uptrend.xyaxis", colorHex: "#45C4B0"),
                    CategoryItemDefinition(name: "押金", icon: "lock.fill", colorHex: "#8E7CFF"),
                ]
            ),
            CategoryGroupDefinition(
                name: "旅行",
                icon: "airplane",
                colorHex: "#5BC0EB",
                children: [
                    CategoryItemDefinition(name: "住宿", icon: "bed.double.fill", colorHex: "#5BC0EB"),
                    CategoryItemDefinition(name: "旅途交通", icon: "airplane", colorHex: "#45C4B0"),
                    CategoryItemDefinition(name: "门票", icon: "ticket.fill", colorHex: "#F7B267"),
                    CategoryItemDefinition(name: "当地餐饮", icon: "fork.knife", colorHex: "#FF9F43"),
                    CategoryItemDefinition(name: "旅行购物", icon: "bag.fill", colorHex: "#70D6A3"),
                    CategoryItemDefinition(name: "签证证件", icon: "doc.badge.ellipsis", colorHex: "#7B8CDE"),
                ]
            ),
            CategoryGroupDefinition(
                name: "其他",
                icon: "ellipsis.circle.fill",
                colorHex: "#9AA6B2",
                children: []
            ),
        ]
    }

    static func incomeCategoryGroups() -> [CategoryGroupDefinition] {
        [
            CategoryGroupDefinition(
                name: "工资",
                icon: "briefcase.fill",
                colorHex: "#2FCB8A",
                children: [
                    CategoryItemDefinition(name: "基本工资", icon: "briefcase.fill", colorHex: "#2FCB8A"),
                    CategoryItemDefinition(name: "奖金", icon: "star.fill", colorHex: "#F7C948"),
                    CategoryItemDefinition(name: "补贴", icon: "plus.circle.fill", colorHex: "#45C4B0"),
                    CategoryItemDefinition(name: "报销", icon: "doc.text.fill", colorHex: "#74B9FF"),
                    CategoryItemDefinition(name: "年终奖", icon: "sparkles", colorHex: "#FFB703"),
                ]
            ),
            CategoryGroupDefinition(
                name: "副业",
                icon: "hammer.fill",
                colorHex: "#FF8A65",
                children: [
                    CategoryItemDefinition(name: "项目款", icon: "folder.fill", colorHex: "#FF8A65"),
                    CategoryItemDefinition(name: "稿费", icon: "pencil.and.outline", colorHex: "#B28DFF"),
                    CategoryItemDefinition(name: "咨询", icon: "person.wave.2.fill", colorHex: "#4D96FF"),
                    CategoryItemDefinition(name: "分成", icon: "percent", colorHex: "#45C4B0"),
                    CategoryItemDefinition(name: "平台收入", icon: "network", colorHex: "#7B8CDE"),
                ]
            ),
            CategoryGroupDefinition(
                name: "投资",
                icon: "chart.line.uptrend.xyaxis",
                colorHex: "#3B82F6",
                children: [
                    CategoryItemDefinition(name: "股息", icon: "chart.pie.fill", colorHex: "#3B82F6"),
                    CategoryItemDefinition(name: "基金", icon: "chart.bar.xaxis", colorHex: "#4E8CFF"),
                    CategoryItemDefinition(name: "理财利息", icon: "percent", colorHex: "#45C4B0"),
                    CategoryItemDefinition(name: "理财收益", icon: "banknote.fill", colorHex: "#2FCB8A"),
                    CategoryItemDefinition(name: "卖出收益", icon: "arrow.up.right.circle.fill", colorHex: "#66D37E"),
                ]
            ),
            CategoryGroupDefinition(
                name: "礼金",
                icon: "envelope.fill",
                colorHex: "#FF6B88",
                children: [
                    CategoryItemDefinition(name: "红包", icon: "envelope.fill", colorHex: "#FF6B88"),
                    CategoryItemDefinition(name: "礼物折现", icon: "gift.fill", colorHex: "#FF8FAB"),
                    CategoryItemDefinition(name: "家人转入", icon: "person.2.fill", colorHex: "#F472B6"),
                    CategoryItemDefinition(name: "人情往来", icon: "arrow.left.arrow.right", colorHex: "#A78BFA"),
                ]
            ),
            CategoryGroupDefinition(
                name: "退款",
                icon: "arrow.uturn.backward.circle.fill",
                colorHex: "#45C4B0",
                children: [
                    CategoryItemDefinition(name: "购物退款", icon: "bag.fill", colorHex: "#70D6A3"),
                    CategoryItemDefinition(name: "押金退回", icon: "lock.open.fill", colorHex: "#8E7CFF"),
                    CategoryItemDefinition(name: "报销到账", icon: "doc.text.fill", colorHex: "#74B9FF"),
                    CategoryItemDefinition(name: "取消订单", icon: "xmark.circle.fill", colorHex: "#9AA6B2"),
                ]
            ),
            CategoryGroupDefinition(
                name: "其他收入",
                icon: "plus.circle.fill",
                colorHex: "#9AA6B2",
                children: []
            ),
        ]
    }

    private static func makeCategories(from groups: [CategoryGroupDefinition], isExpense: Bool) -> [Category] {
        groups.enumerated().flatMap { groupIndex, group in
            let baseSortOrder = groupIndex * 100
            let parent = Category(
                name: group.name,
                icon: group.icon,
                colorHex: group.colorHex,
                isExpense: isExpense,
                sortOrder: baseSortOrder
            )
            let children = group.children.enumerated().map { childIndex, child in
                Category(
                    name: child.name,
                    icon: child.icon,
                    colorHex: child.colorHex,
                    isExpense: isExpense,
                    sortOrder: baseSortOrder + childIndex + 1
                )
            }
            return [parent] + children
        }
    }

    private static func categoryGroups(isExpense: Bool) -> [CategoryGroupDefinition] {
        isExpense ? expenseCategoryGroups() : incomeCategoryGroups()
    }

    private static func legacyRootName(for name: String, isExpense: Bool) -> String? {
        if isExpense {
            return [
                "咖啡奶茶": "餐饮",
                "饮品零食": "餐饮",
                "交通": "出行",
                "加油停车": "出行",
                "服饰美妆": "购物",
                "数码家电": "购物",
                "居住": "居家",
                "房租房贷": "居家",
                "宽带话费": "固定服务",
                "通讯网络": "固定服务",
                "订阅": "固定服务",
                "订阅会员": "固定服务",
                "会员订阅": "固定服务",
                "医疗": "健康",
                "运动健康": "健康",
                "教育学习": "学习",
                "礼物人情": "社交",
            ][name]
        } else {
            return [
                "奖金": "工资",
                "兼职": "副业",
                "报销": "工资",
                "红包转入": "礼金",
            ][name]
        }
    }

    static func archivedLegacyExpenseCategoryNames() -> Set<String> {
        [
            "咖啡奶茶",
            "饮品零食",
            "交通",
            "加油停车",
            "服饰美妆",
            "数码家电",
            "居住",
            "房租房贷",
            "宽带话费",
            "通讯网络",
            "订阅",
            "订阅会员",
            "会员订阅",
            "医疗",
            "运动健康",
            "教育学习",
            "礼物人情",
        ]
    }

    static func rootName(for categoryName: String, isExpense: Bool) -> String {
        let groups = categoryGroups(isExpense: isExpense)
        if groups.contains(where: { $0.name == categoryName }) {
            return categoryName
        }
        if let group = groups.first(where: { group in group.children.contains(where: { $0.name == categoryName }) }) {
            return group.name
        }
        if let legacyRoot = legacyRootName(for: categoryName, isExpense: isExpense) {
            return legacyRoot
        }
        return categoryName
    }

    static func groupDefinition(for rootName: String, isExpense: Bool) -> CategoryGroupDefinition? {
        categoryGroups(isExpense: isExpense).first { $0.name == rootName }
    }

    static func rootCategories(from categories: [Category], isExpense: Bool) -> [Category] {
        let activeCategories = categories.filter { $0.isExpense == isExpense && !$0.isArchived }
        let groups = categoryGroups(isExpense: isExpense)
        var result: [Category] = []
        var seenRoots = Set<String>()

        for group in groups {
            if let root = activeCategories.first(where: { $0.name == group.name })
                ?? activeCategories.first(where: { $0.rootCategoryName == group.name }) {
                result.append(root)
                seenRoots.insert(group.name)
            }
        }

        let uncategorizedRoots = activeCategories
            .filter { !seenRoots.contains($0.rootCategoryName) }
            .sorted { $0.sortOrder < $1.sortOrder }

        for category in uncategorizedRoots where !seenRoots.contains(category.rootCategoryName) {
            result.append(category)
            seenRoots.insert(category.rootCategoryName)
        }

        return result
    }

    static func childCategories(for parentName: String, in categories: [Category], isExpense: Bool) -> [Category] {
        let groups = categoryGroups(isExpense: isExpense)
        let childOrder = Dictionary(
            uniqueKeysWithValues: groups
                .first(where: { $0.name == parentName })?
                .children
                .enumerated()
                .map { ($0.element.name, $0.offset) } ?? []
        )

        return categories
            .filter {
                $0.isExpense == isExpense
                && !$0.isArchived
                && $0.rootCategoryName == parentName
                && $0.name != parentName
            }
            .sorted { lhs, rhs in
                let leftOrder = childOrder[lhs.name] ?? Int.max
                let rightOrder = childOrder[rhs.name] ?? Int.max
                if leftOrder == rightOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return leftOrder < rightOrder
            }
    }

    var rootCategoryName: String {
        Category.rootName(for: name, isExpense: isExpense)
    }

    var entryDisplayName: String {
        rootCategoryName == name ? name : "\(rootCategoryName) · \(name)"
    }

    var reportDisplayName: String {
        rootCategoryName
    }

    var reportIcon: String {
        Category.groupDefinition(for: rootCategoryName, isExpense: isExpense)?.icon ?? icon
    }

    var reportColorHex: String {
        Category.groupDefinition(for: rootCategoryName, isExpense: isExpense)?.colorHex ?? colorHex
    }

    var isSalaryIncome: Bool {
        !isExpense && rootCategoryName == "工资"
    }
}
