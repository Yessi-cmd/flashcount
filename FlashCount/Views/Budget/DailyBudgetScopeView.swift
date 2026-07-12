import SwiftUI
import SwiftData

/// 配置哪些支出分类计入发薪周期日常预算。
struct DailyBudgetScopeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(
        filter: #Predicate<Category> { $0.isExpense == true && $0.isArchived == false },
        sort: \Category.sortOrder
    ) private var categories: [Category]

    @State private var saveError: String?

    private var roots: [Category] {
        Category.rootCategories(from: categories, isExpense: true)
    }

    private var includedCount: Int {
        categories.filter { BudgetScope.includesCategory($0) }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.sectionSpacing) {
                    scopeExplanation

                    ForEach(roots, id: \.id) { root in
                        categoryGroup(root)
                    }
                }
                .padding()
            }
            .background(DesignSystem.surfaceBackground)
            .navigationTitle("日常预算范围")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("恢复默认") { resetToDefaults() }
                        .foregroundStyle(DesignSystem.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(DesignSystem.primaryColor)
                }
            }
            .saveErrorAlert($saveError)
        }
    }

    private var scopeExplanation: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "scope")
                    .font(.headline)
                    .foregroundStyle(DesignSystem.primaryColor)
                    .frame(width: 34, height: 34)
                    .background(DesignSystem.primaryColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("已纳入 \(includedCount) 个分类")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.textPrimary)
                    Text("这里定义默认范围，记账时仍可只覆盖某一笔。")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textSecondary)
                }
            }

            Text(BudgetScope.description)
                .font(.caption)
                .foregroundStyle(DesignSystem.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignSystem.cardPadding)
        .background(DesignSystem.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius, style: .continuous)
                .stroke(DesignSystem.borderColor, lineWidth: 1)
        }
    }

    private func categoryGroup(_ root: Category) -> some View {
        let children = Category.childCategories(
            for: root.rootCategoryName,
            in: categories,
            isExpense: true
        )
        let groupCategories = [root] + children

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: root.reportIcon)
                    .font(.subheadline)
                    .foregroundStyle(DesignSystem.primaryColor)
                    .frame(width: 30, height: 30)
                    .background(DesignSystem.softFill)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(root.rootCategoryName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.textPrimary)
                    Text("已纳入 \(groupCategories.filter { BudgetScope.includesCategory($0) }.count) / \(groupCategories.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(DesignSystem.textTertiary)
                }
                Spacer(minLength: 6)
                groupActionButton("全纳入", systemImage: "checkmark", color: DesignSystem.primaryColor) {
                    setGroup(groupCategories, included: true)
                }
                groupActionButton("全排除", systemImage: "minus", color: DesignSystem.textSecondary) {
                    setGroup(groupCategories, included: false)
                }
            }
            .padding(14)

            if !children.isEmpty {
                Divider().overlay(DesignSystem.dividerColor)

                ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                    Toggle(isOn: categoryBinding(child)) {
                        HStack(spacing: 10) {
                            Image(systemName: child.icon)
                                .font(.caption)
                                .foregroundStyle(DesignSystem.textSecondary)
                                .frame(width: 26)
                            Text(child.name)
                                .font(.subheadline)
                                .foregroundStyle(DesignSystem.textPrimary)
                        }
                    }
                    .tint(DesignSystem.primaryColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    if index < children.count - 1 {
                        Divider()
                            .overlay(DesignSystem.dividerColor)
                            .padding(.leading, 50)
                    }
                }
            }
        }
        .background(DesignSystem.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius, style: .continuous)
                .stroke(DesignSystem.borderColor, lineWidth: 1)
        }
    }

    private func categoryBinding(_ category: Category) -> Binding<Bool> {
        Binding(
            get: { BudgetScope.includesCategory(category) },
            set: { newValue in
                category.dailyBudgetOverride = newValue
                saveChanges()
            }
        )
    }

    private func groupActionButton(
        _ title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .background(DesignSystem.softFill)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func setGroup(_ group: [Category], included: Bool) {
        for category in group {
            category.dailyBudgetOverride = included
        }
        saveChanges()
    }

    private func resetToDefaults() {
        for category in categories {
            category.dailyBudgetOverride = nil
        }
        saveChanges()
        HapticManager.selection()
    }

    private func saveChanges() {
        if let error = safeSave(modelContext) {
            modelContext.rollback()
            saveError = error
        } else {
            HapticManager.selection()
        }
    }
}
