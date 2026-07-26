import XCTest
@testable import FlashCount

/// 分类的层级归属与展示派生值。
///
/// 一级分类是报表聚合和预算归集的单位，所以「一笔账属于哪个一级分类」这个
/// 判断错一次，报表、预算范围和下钻结果会同时错。这里覆盖它的四条来源：
/// 显式父级、内置一级分类、内置子分类、以及旧版分类名的映射。
final class CategoryHierarchyTests: XCTestCase {
    // MARK: - 归属判定

    func testExplicitParentWinsOverEverythingElse() {
        let category = Category(
            name: "咖啡",
            icon: "cup.and.saucer.fill",
            colorHex: "#8B5E3C",
            parentCategoryName: "我的自定义组"
        )
        XCTAssertEqual(category.rootCategoryName, "我的自定义组", "用户设定的父级优先于内置归属")
    }

    func testBuiltInRootIsItsOwnRoot() {
        let root = Category(name: "餐饮", icon: "fork.knife", colorHex: "#FF7A70")
        XCTAssertEqual(root.rootCategoryName, "餐饮")
        XCTAssertEqual(root.entryDisplayName, "餐饮", "一级分类不该显示成「餐饮 · 餐饮」")
    }

    func testBuiltInChildResolvesToItsGroup() {
        let child = Category(name: "外卖", icon: "bag", colorHex: "#FF9F43")
        XCTAssertEqual(child.rootCategoryName, "餐饮", "内置子分类即使没写父级也应归到所属组")
        XCTAssertEqual(child.entryDisplayName, "餐饮 · 外卖")
        XCTAssertEqual(child.reportDisplayName, "餐饮", "报表按一级分类聚合")
    }

    /// 旧版本用过的分类名要能映射回现在的一级分类，否则历史数据会散成一堆孤立分类。
    func testLegacyNamesMapToTheirCurrentGroup() {
        for (legacy, expectedRoot) in [
            ("会员订阅", "固定服务"),
            ("医疗", "健康"),
            ("运动健康", "健康"),
            ("教育学习", "学习"),
            ("礼物人情", "社交")
        ] {
            let category = Category(name: legacy, icon: "tag", colorHex: "#111111")
            XCTAssertEqual(category.rootCategoryName, expectedRoot, "旧分类「\(legacy)」应归到「\(expectedRoot)」")
        }

        for (legacy, expectedRoot) in [("奖金", "工资"), ("兼职", "副业"), ("报销", "工资"), ("红包转入", "礼金")] {
            let category = Category(name: legacy, icon: "tag", colorHex: "#111111", isExpense: false)
            XCTAssertEqual(category.rootCategoryName, expectedRoot, "旧收入分类「\(legacy)」应归到「\(expectedRoot)」")
        }
    }

    /// 完全认不出的名字就以自己为一级分类——不能凭空塞进某个组里。
    func testUnknownNameBecomesItsOwnRoot() {
        let category = Category(name: "只有我知道的分类", icon: "tag", colorHex: "#111111")
        XCTAssertEqual(category.rootCategoryName, "只有我知道的分类")
    }

    /// 同名的收入与支出分类互不干扰。
    func testResolutionIsScopedByExpenseType() {
        XCTAssertEqual(Category.rootName(for: "奖金", isExpense: false), "工资")
        XCTAssertEqual(
            Category.rootName(for: "奖金", isExpense: true),
            "奖金",
            "支出侧没有「奖金」这个内置子分类，应以自己为一级分类"
        )
    }

    // MARK: - defaultKey

    func testDefaultKeyIsNamespacedByExpenseType() {
        XCTAssertEqual(Category.defaultKey(for: "餐饮", isExpense: true), "expense.餐饮")
        XCTAssertEqual(Category.defaultKey(for: "餐饮", isExpense: false), "income.餐饮")
        XCTAssertNotEqual(
            Category.defaultKey(for: "奖金", isExpense: true),
            Category.defaultKey(for: "奖金", isExpense: false)
        )
    }

    func testDefaultRootNameResolvesBothRootsAndChildren() {
        XCTAssertEqual(
            Category.defaultRootName(forDefaultKey: Category.defaultKey(for: "餐饮", isExpense: true), isExpense: true),
            "餐饮"
        )
        XCTAssertEqual(
            Category.defaultRootName(forDefaultKey: Category.defaultKey(for: "外卖", isExpense: true), isExpense: true),
            "餐饮",
            "子分类的 key 也要能查回所属组"
        )
        XCTAssertNil(Category.defaultRootName(forDefaultKey: nil, isExpense: true))
        XCTAssertNil(Category.defaultRootName(forDefaultKey: "expense.不存在", isExpense: true))
    }

    func testDefaultParentNameFindsTheOwningGroup() {
        XCTAssertEqual(Category.defaultParentName(for: "外卖", isExpense: true), "餐饮")
        XCTAssertNil(Category.defaultParentName(for: "餐饮", isExpense: true), "一级分类本身没有父级")
        XCTAssertNil(Category.defaultParentName(for: "自定义", isExpense: true))
    }

    func testGroupDefinitionLookup() {
        let group = Category.groupDefinition(for: "餐饮", isExpense: true)
        XCTAssertEqual(group?.name, "餐饮")
        XCTAssertFalse(group?.children.isEmpty ?? true, "餐饮应带有子分类")
        XCTAssertNil(Category.groupDefinition(for: "餐饮", isExpense: false), "收入侧没有餐饮组")
    }

    // MARK: - 列表筛选与排序

    func testRootCategoriesExcludeChildrenArchivedAndOtherType() {
        let root = Category(name: "餐饮", icon: "fork.knife", colorHex: "#111111", sortOrder: 2)
        let secondRoot = Category(name: "出行", icon: "bus", colorHex: "#222222", sortOrder: 1)
        let child = Category(name: "外卖", icon: "bag", colorHex: "#333333", sortOrder: 3)
        let archived = Category(name: "购物", icon: "basket", colorHex: "#444444", sortOrder: 0)
        archived.isArchived = true
        let income = Category(name: "工资", icon: "banknote", colorHex: "#555555", isExpense: false, sortOrder: 0)

        let roots = Category.rootCategories(from: [root, secondRoot, child, archived, income], isExpense: true)

        XCTAssertEqual(roots.map(\.name), ["出行", "餐饮"], "按 sortOrder 排序，且排除子分类/归档/收入侧")
    }

    func testChildCategoriesExcludeTheParentItselfAndArchived() {
        let root = Category(name: "餐饮", icon: "fork.knife", colorHex: "#111111", sortOrder: 0)
        let child = Category(name: "外卖", icon: "bag", colorHex: "#222222", sortOrder: 2)
        let anotherChild = Category(name: "正餐", icon: "fork", colorHex: "#333333", sortOrder: 1)
        let archivedChild = Category(name: "咖啡", icon: "cup", colorHex: "#444444", sortOrder: 3)
        archivedChild.isArchived = true

        let children = Category.childCategories(
            for: "餐饮",
            in: [root, child, anotherChild, archivedChild],
            isExpense: true
        )

        XCTAssertEqual(children.map(\.name), ["正餐", "外卖"], "不含一级分类自身与已归档的子分类")
    }

    /// sortOrder 相同时按名称定序，避免列表顺序在每次启动后随机变化。
    func testEqualSortOrderFallsBackToNameOrdering() {
        let first = Category(name: "出行", icon: "bus", colorHex: "#111111", sortOrder: 5)
        let second = Category(name: "餐饮", icon: "fork.knife", colorHex: "#222222", sortOrder: 5)

        let rootsOneOrder = Category.rootCategories(from: [first, second], isExpense: true).map(\.name)
        let rootsOtherOrder = Category.rootCategories(from: [second, first], isExpense: true).map(\.name)

        XCTAssertEqual(rootsOneOrder, rootsOtherOrder, "输入顺序不该影响结果")
    }

    // MARK: - 报表展示派生值

    /// 子分类在报表里应借用所属组的图标与颜色，这样同组的条目视觉上是一体的。
    func testChildBorrowsGroupIconAndColorForReports() {
        let child = Category(
            name: "外卖",
            icon: "questionmark",
            colorHex: "#000000",
            defaultKey: Category.defaultKey(for: "外卖", isExpense: true)
        )
        let group = Category.groupDefinition(for: "餐饮", isExpense: true)

        XCTAssertEqual(child.reportIcon, group?.icon)
        XCTAssertEqual(child.reportColorHex, group?.colorHex)
    }

    func testRootKeepsItsOwnIconAndColorForReports() {
        let root = Category(name: "餐饮", icon: "custom.icon", colorHex: "#ABCDEF")
        XCTAssertEqual(root.reportIcon, "custom.icon")
        XCTAssertEqual(root.reportColorHex, "#ABCDEF")
    }

    /// 自定义子分类没有内置 key 时，保留自己的图标与颜色而不是回落到别的组。
    func testCustomChildWithoutDefaultKeyKeepsItsOwnAppearance() {
        let child = Category(
            name: "我的小类",
            icon: "star.fill",
            colorHex: "#123456",
            parentCategoryName: "我的组"
        )
        XCTAssertEqual(child.reportIcon, "star.fill")
        XCTAssertEqual(child.reportColorHex, "#123456")
    }
}
