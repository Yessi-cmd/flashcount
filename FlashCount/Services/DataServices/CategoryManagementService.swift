import Foundation
import SwiftData

enum CategoryManagementError: LocalizedError, Equatable {
    case invalidName
    case duplicateName
    case invalidParent
    case lastActiveCategory
    case mergedCategoryCannotRestore
    case invalidMergeTarget

    var errorDescription: String? {
        switch self {
        case .invalidName: return "分类名称需要为 1 到 24 个字符。"
        case .duplicateName: return "同一收支类型下已经存在同名分类。"
        case .invalidParent: return "只能选择同一收支类型下的一级分类作为父级。"
        case .lastActiveCategory: return "至少需要保留一个可用的一级分类。"
        case .mergedCategoryCannotRestore: return "该分类已经合并到其他分类，不能直接恢复。"
        case .invalidMergeTarget: return "请选择同一收支类型下的有效合并目标。"
        }
    }
}

@MainActor
final class CategoryManagementService {
    enum MoveDirection { case up, down }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func create(
        name: String,
        icon: String,
        colorHex: String,
        isExpense: Bool,
        parent: Category?
    ) throws -> Category {
        let cleanName = try validatedName(name)
        let categories = try allCategories()
        try validateUniqueName(cleanName, isExpense: isExpense, excluding: nil, categories: categories)
        try validate(parent: parent, for: nil, isExpense: isExpense, categories: categories)

        let sortOrder: Int
        if let parent {
            let children = children(of: parent, in: categories)
            sortOrder = (children.map(\.sortOrder).max() ?? parent.sortOrder) + 1
        } else {
            sortOrder = (roots(isExpense: isExpense, in: categories).map(\.sortOrder).max() ?? -1_000) + 1_000
        }

        let category = Category(
            name: cleanName,
            icon: icon,
            colorHex: colorHex,
            isExpense: isExpense,
            sortOrder: sortOrder,
            parentCategoryName: parent?.name
        )
        modelContext.insert(category)
        try commit()
        return category
    }

    func update(
        _ category: Category,
        name: String,
        icon: String,
        colorHex: String,
        parent: Category?
    ) throws {
        let cleanName = try validatedName(name)
        let categories = try allCategories()
        try validateUniqueName(
            cleanName,
            isExpense: category.isExpense,
            excluding: category.id,
            categories: categories
        )
        try validate(parent: parent, for: category, isExpense: category.isExpense, categories: categories)

        let oldName = category.name
        let categoryChildren = children(of: category, in: categories)
        if parent != nil, !categoryChildren.isEmpty {
            throw CategoryManagementError.invalidParent
        }

        category.name = cleanName
        category.icon = icon
        category.colorHex = colorHex
        category.parentCategoryName = parent?.name

        if oldName != cleanName {
            for child in categoryChildren {
                child.parentCategoryName = cleanName
            }
            let templates = try modelContext.fetch(FetchDescriptor<TransactionTemplate>())
            for template in templates where template.isExpense == category.isExpense && template.categoryName == oldName {
                template.categoryName = cleanName
            }
        }

        if let parent {
            let siblings = children(of: parent, in: categories).filter { $0.id != category.id }
            category.sortOrder = (siblings.map(\.sortOrder).max() ?? parent.sortOrder) + 1
        }
        try commit()
    }

    func archive(_ category: Category) throws {
        let categories = try allCategories()
        if category.rootCategoryName == category.name,
           roots(isExpense: category.isExpense, in: categories).count <= 1 {
            throw CategoryManagementError.lastActiveCategory
        }

        category.isArchived = true
        if category.rootCategoryName == category.name {
            for child in children(of: category, in: categories) {
                child.isArchived = true
            }
        }
        try commit()
    }

    func restore(_ category: Category) throws {
        guard category.mergedIntoCategoryID == nil else {
            throw CategoryManagementError.mergedCategoryCannotRestore
        }
        let categories = try allCategories()
        try validateUniqueName(
            category.name,
            isExpense: category.isExpense,
            excluding: category.id,
            categories: categories.filter { !$0.isArchived }
        )

        category.isArchived = false
        if category.rootCategoryName == category.name {
            for child in children(of: category, in: categories) where child.mergedIntoCategoryID == nil {
                child.isArchived = false
            }
        } else if let parent = categories.first(where: {
            $0.isExpense == category.isExpense && $0.name == category.rootCategoryName
        }), parent.mergedIntoCategoryID == nil {
            parent.isArchived = false
        }
        try commit()
    }

    func move(_ category: Category, direction: MoveDirection) throws {
        let categories = try allCategories()
        let siblings: [Category]
        if category.rootCategoryName == category.name {
            siblings = roots(isExpense: category.isExpense, in: categories)
        } else if let parent = categories.first(where: {
            $0.isExpense == category.isExpense && $0.name == category.rootCategoryName
        }) {
            siblings = children(of: parent, in: categories).filter { !$0.isArchived }
        } else {
            throw CategoryManagementError.invalidParent
        }

        guard let index = siblings.firstIndex(where: { $0.id == category.id }) else { return }
        let targetIndex = direction == .up ? index - 1 : index + 1
        guard siblings.indices.contains(targetIndex) else { return }

        var reordered = siblings
        reordered.swapAt(index, targetIndex)
        if category.rootCategoryName == category.name {
            normalizeRootOrder(reordered, categories: categories)
        } else {
            let base = categories.first(where: { $0.name == category.rootCategoryName && $0.isExpense == category.isExpense })?.sortOrder ?? 0
            for (offset, item) in reordered.enumerated() {
                item.sortOrder = base + offset + 1
            }
        }
        try commit()
    }

    func merge(_ source: Category, into target: Category) throws {
        let categories = try allCategories()
        guard source.id != target.id,
              source.isExpense == target.isExpense,
              !target.isArchived,
              target.mergedIntoCategoryID == nil else {
            throw CategoryManagementError.invalidMergeTarget
        }

        let sourceChildren = children(of: source, in: categories)
        if !sourceChildren.isEmpty, target.rootCategoryName != target.name {
            throw CategoryManagementError.invalidMergeTarget
        }

        for transaction in source.transactions {
            transaction.category = target
        }
        for rule in source.recurringRules {
            rule.category = target
        }

        let budgets = try modelContext.fetch(FetchDescriptor<Budget>())
        let sourceBudgets = budgets.filter { $0.categoryId == source.id }
        for sourceBudget in sourceBudgets {
            if let targetBudget = budgets.first(where: {
                $0.id != sourceBudget.id
                    && $0.categoryId == target.id
                    && $0.year == sourceBudget.year
                    && $0.month == sourceBudget.month
                    && sameLedger($0.ledger, sourceBudget.ledger)
            }) {
                targetBudget.monthlyLimit += sourceBudget.monthlyLimit
                modelContext.delete(sourceBudget)
            } else {
                sourceBudget.categoryId = target.id
            }
        }

        let templates = try modelContext.fetch(FetchDescriptor<TransactionTemplate>())
        for template in templates where template.isExpense == source.isExpense && template.categoryName == source.name {
            template.categoryName = target.name
        }

        for child in sourceChildren {
            child.parentCategoryName = target.name
        }
        if target.dailyBudgetOverride == nil {
            target.dailyBudgetOverride = source.dailyBudgetOverride
        }
        source.isArchived = true
        source.mergedIntoCategoryID = target.id
        try commit()
    }

    private func validatedName(_ name: String) throws -> String {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.count <= 24 else {
            throw CategoryManagementError.invalidName
        }
        return cleanName
    }

    private func validateUniqueName(
        _ name: String,
        isExpense: Bool,
        excluding excludedID: UUID?,
        categories: [Category]
    ) throws {
        if categories.contains(where: {
            $0.isExpense == isExpense
                && $0.id != excludedID
                && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            throw CategoryManagementError.duplicateName
        }
    }

    private func validate(
        parent: Category?,
        for category: Category?,
        isExpense: Bool,
        categories: [Category]
    ) throws {
        guard let parent else { return }
        guard parent.id != category?.id,
              parent.isExpense == isExpense,
              !parent.isArchived,
              parent.mergedIntoCategoryID == nil,
              parent.rootCategoryName == parent.name,
              categories.contains(where: { $0.id == parent.id }) else {
            throw CategoryManagementError.invalidParent
        }
    }

    private func allCategories() throws -> [Category] {
        try modelContext.fetch(FetchDescriptor<Category>())
    }

    private func roots(isExpense: Bool, in categories: [Category]) -> [Category] {
        Category.rootCategories(from: categories, isExpense: isExpense)
    }

    private func children(of parent: Category, in categories: [Category]) -> [Category] {
        categories
            .filter {
                $0.id != parent.id
                    && $0.isExpense == parent.isExpense
                    && $0.rootCategoryName == parent.name
            }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    private func normalizeRootOrder(_ roots: [Category], categories: [Category]) {
        for (rootIndex, root) in roots.enumerated() {
            let base = rootIndex * 1_000
            root.sortOrder = base
            for (childIndex, child) in children(of: root, in: categories).enumerated() {
                child.sortOrder = base + childIndex + 1
            }
        }
    }

    private func sameLedger(_ lhs: Ledger?, _ rhs: Ledger?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case (.some(let lhs), .some(let rhs)): return lhs.id == rhs.id
        default: return false
        }
    }

    private func commit() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
