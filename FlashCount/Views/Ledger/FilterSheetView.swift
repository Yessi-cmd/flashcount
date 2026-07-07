import SwiftUI
import SwiftData

// MARK: - 筛选类型

enum TransactionTypeFilter: String, CaseIterable {
    case all = "全部"
    case expense = "支出"
    case income = "收入"
}

// MARK: - 筛选面板

struct FilterSheetView: View {
    @Query(
        filter: #Predicate<Category> { !$0.isArchived },
        sort: \Category.sortOrder
    ) private var allCategories: [Category]

    @Binding var typeFilter: TransactionTypeFilter
    @Binding var categoryFilterId: UUID?
    @Binding var minAmountText: String
    @Binding var maxAmountText: String

    @Environment(\.dismiss) private var dismiss

    @State private var expandedRootId: UUID?

    private var visibleRootCategories: [Category] {
        let isExpenseOnly = typeFilter == .expense
        if typeFilter == .all {
            return Category.rootCategories(from: allCategories, isExpense: true)
                + Category.rootCategories(from: allCategories, isExpense: false)
        }
        return Category.rootCategories(from: allCategories, isExpense: isExpenseOnly)
    }

    // 当前选中分类的详细信息
    private var selectedCategoryInfo: (name: String, isRoot: Bool)? {
        guard let id = categoryFilterId,
              let cat = allCategories.first(where: { $0.id == id }) else { return nil }
        return (cat.entryDisplayName, cat.rootCategoryName == cat.name)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.sectionSpacing) {
                    // 交易类型
                    typeSection

                    // 分类
                    categorySection

                    // 金额范围
                    amountSection
                }
                .padding()
            }
            .background(DesignSystem.surfaceBackground)
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("重置") {
                        withAnimation { resetAll() }
                        HapticManager.selection()
                    }
                    .foregroundStyle(DesignSystem.primaryColor)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(DesignSystem.primaryColor)
                }
            }
        }
    }

    // MARK: - 交易类型

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("交易类型", icon: "arrow.left.arrow.right")

            Picker("类型", selection: $typeFilter) {
                ForEach(TransactionTypeFilter.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: typeFilter) { _, newValue in
                // 切换类型时，如果当前选中的分类与类型不匹配，清除分类
                if let id = categoryFilterId,
                   let cat = allCategories.first(where: { $0.id == id }) {
                    let isExpenseType = newValue == .expense
                    let isIncomeType = newValue == .income
                    if (isExpenseType && !cat.isExpense) || (isIncomeType && cat.isExpense) {
                        withAnimation { categoryFilterId = nil }
                    }
                }
                expandedRootId = nil
            }
        }
    }

    // MARK: - 分类

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("分类", icon: "tag.fill")

            // 已选标签
            if let info = selectedCategoryInfo {
                HStack(spacing: 8) {
                    Image(systemName: info.isRoot ? "folder.fill" : "tag.fill")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.primaryColor)
                    Text(info.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DesignSystem.textPrimary)
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            categoryFilterId = nil
                            expandedRootId = nil
                        }
                        HapticManager.selection()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(DesignSystem.textTertiary)
                    }
                }
                .padding(10)
                .background(DesignSystem.primaryColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // 分类网格
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(visibleRootCategories, id: \.id) { root in
                    let children = Category.childCategories(for: root.name, in: allCategories, isExpense: root.isExpense)
                    let isSelected = categoryFilterId == root.id
                    let isExpanded = expandedRootId == root.id

                    VStack(spacing: 4) {
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                if isSelected {
                                    categoryFilterId = nil
                                    expandedRootId = nil
                                } else if !children.isEmpty {
                                    // 展开子分类
                                    categoryFilterId = root.id
                                    expandedRootId = isExpanded ? nil : root.id
                                } else {
                                    categoryFilterId = root.id
                                    expandedRootId = nil
                                }
                            }
                            HapticManager.selection()
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(isSelected ? Color(hex: root.colorHex).opacity(0.2) : DesignSystem.softFill)
                                        .frame(width: 48, height: 48)
                                    Image(systemName: root.icon)
                                        .font(.title3)
                                        .foregroundStyle(isSelected ? Color(hex: root.colorHex) : DesignSystem.textSecondary)
                                }
                                Text(root.name)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(isSelected ? DesignSystem.textPrimary : DesignSystem.textSecondary)
                                    .lineLimit(1)
                            }
                        }

                        // 子分类（展开时）
                        if isExpanded && !children.isEmpty {
                            VStack(spacing: 6) {
                                ForEach(children, id: \.id) { child in
                                    Button {
                                        withAnimation(.spring(response: 0.3)) {
                                            categoryFilterId = child.id
                                        }
                                        HapticManager.selection()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(categoryFilterId == child.id ? Color(hex: child.colorHex).opacity(0.2) : Color.clear)
                                                .frame(width: 8, height: 8)
                                                .overlay(
                                                    Circle()
                                                        .stroke(Color(hex: child.colorHex).opacity(0.4), lineWidth: 1.5)
                                                )
                                            Text(child.name)
                                                .font(.caption)
                                                .foregroundStyle(categoryFilterId == child.id ? Color(hex: child.colorHex) : DesignSystem.textSecondary)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                            .padding(.leading, 4)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 金额范围

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("金额范围", icon: "dollarsign.circle.fill")

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("¥")
                        .font(.subheadline)
                        .foregroundStyle(DesignSystem.textTertiary)
                    TextField("最低", text: $minAmountText)
                        .keyboardType(.decimalPad)
                        .font(.subheadline)
                        .foregroundStyle(DesignSystem.textPrimary)
                }
                .padding(10)
                .background(DesignSystem.softFill)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))

                Text("—")
                    .foregroundStyle(DesignSystem.textTertiary)

                HStack(spacing: 4) {
                    Text("¥")
                        .font(.subheadline)
                        .foregroundStyle(DesignSystem.textTertiary)
                    TextField("最高", text: $maxAmountText)
                        .keyboardType(.decimalPad)
                        .font(.subheadline)
                        .foregroundStyle(DesignSystem.textPrimary)
                }
                .padding(10)
                .background(DesignSystem.softFill)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
            }
        }
    }

    // MARK: - 辅助

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(DesignSystem.primaryColor)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.textPrimary)
        }
    }

    private func resetAll() {
        typeFilter = .all
        categoryFilterId = nil
        minAmountText = ""
        maxAmountText = ""
        expandedRootId = nil
    }
}
