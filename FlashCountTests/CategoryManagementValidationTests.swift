import SwiftData
import XCTest
@testable import FlashCount

/// 分类的新建、校验、排序与恢复。
///
/// 现有的 `CategoryManagementServiceTests` 覆盖了改名、合并、归档三条主路径；
/// 这里补的是校验与边界——分类被交易、周期规则、预算和模板同时引用，
/// 一次放行错的输入就会留下指向不存在分类的记录。
@MainActor
final class CategoryManagementValidationTests: XCTestCase {
    // MARK: - 名称校验

    func testNameMustNotBeEmptyOrOverLimit() throws {
        let (context, service) = try makeService()

        for badName in ["", "   ", String(repeating: "长", count: 25)] {
            XCTAssertThrowsError(
                try service.create(name: badName, icon: "tag", colorHex: "#111111", isExpense: true, parent: nil),
                "名称 \(badName.count) 字应被拒绝"
            ) { error in
                XCTAssertEqual(error as? CategoryManagementError, .invalidName)
            }
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FlashCount.Category>()), 0)
    }

    func testNameIsTrimmedAndBoundaryLengthIsAccepted() throws {
        let (_, service) = try makeService()

        let trimmed = try service.create(name: "  日常  ", icon: "tag", colorHex: "#111111", isExpense: true, parent: nil)
        XCTAssertEqual(trimmed.name, "日常", "首尾空白应被裁掉，否则会出现看起来同名的两个分类")

        let maxLength = String(repeating: "长", count: 24)
        let atLimit = try service.create(name: maxLength, icon: "tag", colorHex: "#111111", isExpense: true, parent: nil)
        XCTAssertEqual(atLimit.name, maxLength, "24 字是上限内的合法值")
    }

    /// 同名判断限定在同一收支类型内：支出「奖金」和收入「奖金」可以共存。
    func testDuplicateNameIsRejectedWithinSameExpenseTypeOnly() throws {
        let (_, service) = try makeService()
        _ = try service.create(name: "奖金", icon: "gift", colorHex: "#111111", isExpense: true, parent: nil)

        XCTAssertThrowsError(
            try service.create(name: "奖金", icon: "gift", colorHex: "#222222", isExpense: true, parent: nil)
        ) { error in
            XCTAssertEqual(error as? CategoryManagementError, .duplicateName)
        }

        XCTAssertNoThrow(
            try service.create(name: "奖金", icon: "gift", colorHex: "#333333", isExpense: false, parent: nil),
            "收入侧的同名分类应允许"
        )
    }

    func testRenamingToAnExistingNameIsRejected() throws {
        let (_, service) = try makeService()
        _ = try service.create(name: "餐饮", icon: "fork.knife", colorHex: "#111111", isExpense: true, parent: nil)
        let other = try service.create(name: "出行", icon: "bus", colorHex: "#222222", isExpense: true, parent: nil)

        XCTAssertThrowsError(
            try service.update(other, name: "餐饮", icon: "bus", colorHex: "#222222", parent: nil)
        ) { error in
            XCTAssertEqual(error as? CategoryManagementError, .duplicateName)
        }
        XCTAssertEqual(other.name, "出行", "校验失败不该留下半改的名字")
    }

    /// 改名成自己是合法的（用户可能只想换图标或颜色）。
    func testUpdatingIconOnlyKeepsTheSameNameValid() throws {
        let (_, service) = try makeService()
        let category = try service.create(name: "餐饮", icon: "fork.knife", colorHex: "#111111", isExpense: true, parent: nil)

        try service.update(category, name: "餐饮", icon: "cup.and.saucer.fill", colorHex: "#999999", parent: nil)

        XCTAssertEqual(category.name, "餐饮")
        XCTAssertEqual(category.icon, "cup.and.saucer.fill")
        XCTAssertEqual(category.colorHex, "#999999")
    }

    // MARK: - 父级校验

    func testParentMustBeARootOfTheSameExpenseType() throws {
        let (_, service) = try makeService()
        let expenseRoot = try service.create(name: "餐饮", icon: "fork.knife", colorHex: "#111111", isExpense: true, parent: nil)
        let incomeRoot = try service.create(name: "工资", icon: "banknote", colorHex: "#222222", isExpense: false, parent: nil)
        let child = try service.create(name: "外卖", icon: "takeoutbag.and.cup.and.straw.fill", colorHex: "#333333", isExpense: true, parent: expenseRoot)

        // 跨收支类型的父级
        XCTAssertThrowsError(
            try service.create(name: "夜宵", icon: "moon", colorHex: "#444444", isExpense: true, parent: incomeRoot)
        ) { error in
            XCTAssertEqual(error as? CategoryManagementError, .invalidParent)
        }

        // 子分类不能再当父级（只支持两层）
        XCTAssertThrowsError(
            try service.create(name: "更深", icon: "moon", colorHex: "#555555", isExpense: true, parent: child)
        ) { error in
            XCTAssertEqual(error as? CategoryManagementError, .invalidParent)
        }
    }

    /// 有子分类的一级分类不能被降级成别人的子分类——否则会出现三层结构。
    func testRootWithChildrenCannotBecomeAChild() throws {
        let (_, service) = try makeService()
        let root = try service.create(name: "餐饮", icon: "fork.knife", colorHex: "#111111", isExpense: true, parent: nil)
        _ = try service.create(name: "外卖", icon: "bag", colorHex: "#222222", isExpense: true, parent: root)
        let otherRoot = try service.create(name: "购物", icon: "basket", colorHex: "#333333", isExpense: true, parent: nil)

        XCTAssertThrowsError(
            try service.update(root, name: "餐饮", icon: "fork.knife", colorHex: "#111111", parent: otherRoot)
        ) { error in
            XCTAssertEqual(error as? CategoryManagementError, .invalidParent)
        }
        XCTAssertNil(root.parentCategoryName, "校验失败不该留下半改的父级")
    }

    // MARK: - 排序

    func testMoveSwapsWithTheNeighbourAndStopsAtTheEdges() throws {
        let (_, service) = try makeService()
        let first = try service.create(name: "甲", icon: "1.circle", colorHex: "#111111", isExpense: true, parent: nil)
        let second = try service.create(name: "乙", icon: "2.circle", colorHex: "#222222", isExpense: true, parent: nil)

        XCTAssertLessThan(first.sortOrder, second.sortOrder)

        try service.move(second, direction: .up)
        XCTAssertLessThan(second.sortOrder, first.sortOrder, "上移后应排在前面")

        // 已经在头部，再上移应是无操作而不是报错或越界
        let secondBefore = second.sortOrder
        let firstBefore = first.sortOrder
        try service.move(second, direction: .up)
        XCTAssertEqual(second.sortOrder, secondBefore)
        XCTAssertEqual(first.sortOrder, firstBefore)

        try service.move(second, direction: .down)
        XCTAssertLessThan(first.sortOrder, second.sortOrder, "下移应换回去")
    }

    // MARK: - 恢复

    func testRestoringBringsBackTheParentSoTheChildIsReachable() throws {
        let (_, service) = try makeService()
        let root = try service.create(name: "餐饮", icon: "fork.knife", colorHex: "#111111", isExpense: true, parent: nil)
        let child = try service.create(name: "外卖", icon: "bag", colorHex: "#222222", isExpense: true, parent: root)
        _ = try service.create(name: "保底", icon: "tag", colorHex: "#333333", isExpense: true, parent: nil)

        try service.archive(root)
        XCTAssertTrue(root.isArchived)
        XCTAssertTrue(child.isArchived, "归档一级分类应级联到子分类")

        try service.restore(child)
        XCTAssertFalse(child.isArchived)
        XCTAssertFalse(root.isArchived, "恢复子分类必须把父级一起恢复，否则它挂在一个隐藏的父级下")
    }

    /// 已合并出去的分类不能直接恢复——它的引用都已经迁走了。
    func testMergedCategoryCannotBeRestored() throws {
        let (_, service) = try makeService()
        let source = try service.create(name: "旧分类", icon: "tag", colorHex: "#111111", isExpense: true, parent: nil)
        let target = try service.create(name: "新分类", icon: "tag", colorHex: "#222222", isExpense: true, parent: nil)

        try service.merge(source, into: target)

        XCTAssertThrowsError(try service.restore(source)) { error in
            XCTAssertEqual(error as? CategoryManagementError, .mergedCategoryCannotRestore)
        }
    }

    func testMergeRejectsInvalidTargets() throws {
        let (_, service) = try makeService()
        let source = try service.create(name: "甲", icon: "tag", colorHex: "#111111", isExpense: true, parent: nil)
        let archived = try service.create(name: "乙", icon: "tag", colorHex: "#222222", isExpense: true, parent: nil)
        let income = try service.create(name: "丙", icon: "tag", colorHex: "#333333", isExpense: false, parent: nil)
        _ = try service.create(name: "保底", icon: "tag", colorHex: "#444444", isExpense: true, parent: nil)
        try service.archive(archived)

        // 合并到自己
        XCTAssertThrowsError(try service.merge(source, into: source)) { error in
            XCTAssertEqual(error as? CategoryManagementError, .invalidMergeTarget)
        }
        // 合并到已归档的分类
        XCTAssertThrowsError(try service.merge(source, into: archived)) { error in
            XCTAssertEqual(error as? CategoryManagementError, .invalidMergeTarget)
        }
        // 跨收支类型合并
        XCTAssertThrowsError(try service.merge(source, into: income)) { error in
            XCTAssertEqual(error as? CategoryManagementError, .invalidMergeTarget)
        }
    }

    // MARK: - 夹具

    private func makeService() throws -> (ModelContext, CategoryManagementService) {
        let container = try ModelContainer(
            for: Schema(versionedSchema: FlashCountSchemaV3.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        return (context, CategoryManagementService(modelContext: context))
    }
}
