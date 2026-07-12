import SwiftUI
import SwiftData

/// 添加周期性规则
struct AddRecurringRuleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Ledger.sortOrder) private var ledgers: [Ledger]
    @Query(filter: #Predicate<Category> { $0.isExpense == true && $0.isArchived == false }, sort: \Category.sortOrder) private var expenseCategories: [Category]
    @Query(filter: #Predicate<Category> { $0.isExpense == false && $0.isArchived == false }, sort: \Category.sortOrder) private var incomeCategories: [Category]

    var editRule: RecurringRule?
    @State private var title = ""
    @State private var amountText = ""
    @State private var frequency: RecurringFrequency = .monthly
    @State private var nextDueDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var selectedCategory: Category?
    @State private var selectedLedger: Ledger?
    @State private var isExpense = true
    @State private var wheelCategory: Category?
    @State private var wheelSourceFrame: CGRect?
    @State private var saveError: String?
    @State private var didLoadInitialValues = false

    private var isEditing: Bool {
        editRule != nil
    }

    private var categories: [Category] {
        isExpense ? expenseCategories : incomeCategories
    }

    private var rootCategories: [Category] {
        Category.rootCategories(from: categories, isExpense: isExpense)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        HStack(spacing: 0) {
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    isExpense = true
                                    selectedCategory = defaultCategory()
                                }
                            } label: {
                                Text("支出")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(isExpense ? DesignSystem.expenseColor.opacity(0.2) : .clear)
                                    .foregroundStyle(isExpense ? DesignSystem.expenseColor : DesignSystem.textSecondary)
                            }
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    isExpense = false
                                    selectedCategory = defaultCategory()
                                }
                            } label: {
                                Text("收入")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(!isExpense ? DesignSystem.incomeColor.opacity(0.2) : .clear)
                                    .foregroundStyle(!isExpense ? DesignSystem.incomeColor : DesignSystem.textSecondary)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                        .overlay(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius).stroke(DesignSystem.borderColor, lineWidth: 1))

                        // 名称
                        VStack(alignment: .leading, spacing: 8) {
                            Text("名称").font(.caption.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
                            TextField("例如：房租、话费、Netflix", text: $title).font(.body).foregroundStyle(DesignSystem.textPrimary)
                                .padding(12).background(DesignSystem.softFill)
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("设置结束日期", isOn: $hasEndDate)
                            if hasEndDate {
                                DatePicker("结束日期", selection: $endDate, in: nextDueDate..., displayedComponents: .date)
                            }
                        }

                        // 金额
                        VStack(alignment: .leading, spacing: 8) {
                            Text("金额").font(.caption.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
                            HStack {
                                Text("¥").font(.title3).foregroundStyle(DesignSystem.textSecondary)
                                TextField("0.00", text: $amountText).keyboardType(.decimalPad)
                                    .font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(DesignSystem.textPrimary)
                            }
                            .padding(12).background(DesignSystem.softFill)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                        }

                        // 频率
                        VStack(alignment: .leading, spacing: 8) {
                            Text("频率").font(.caption.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
                            HStack(spacing: 8) {
                                ForEach(RecurringFrequency.allCases, id: \.rawValue) { freq in
                                    Button { frequency = freq } label: {
                                        Text(freq.rawValue).font(.caption.weight(.medium))
                                            .padding(.horizontal, 14).padding(.vertical, 8)
                                            .background(frequency == freq ? DesignSystem.primaryColor.opacity(0.2) : DesignSystem.softFill)
                                            .foregroundStyle(frequency == freq ? DesignSystem.primaryColor : DesignSystem.textSecondary)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }

                        // 下次日期
                        VStack(alignment: .leading, spacing: 8) {
                            Text(isExpense ? "下次扣款日" : "下次入账日").font(.caption.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
                            DatePicker("", selection: $nextDueDate, displayedComponents: .date)
                                .datePickerStyle(.compact).labelsHidden()
                        }

                        // 分类
                        VStack(alignment: .leading, spacing: 8) {
                            Text("分类").font(.caption.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                                ForEach(rootCategories, id: \.id) { category in
                                    let children = Category.childCategories(for: category.rootCategoryName, in: categories, isExpense: isExpense)
                                    CategorySelectionTile(
                                        category: category,
                                        selectedCategory: selectedCategory,
                                        hasChildren: !children.isEmpty,
                                        iconSize: .subheadline,
                                        circleSize: 44,
                                        minHeight: 66,
                                        onSelect: { _ in selectCategory(category) },
                                        onOpenChildren: { sourceFrame in
                                            showWheel(for: category, sourceFrame: sourceFrame)
                                        }
                                    )
                                }
                            }
                        }

                        Spacer()
                    }
                    .padding()
                }
            }
            .overlay {
                if let wheelCategory {
                    categoryWheel(for: wheelCategory)
                }
            }
            .navigationTitle(isEditing ? "编辑周期账单" : "添加周期账单").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() }.foregroundStyle(DesignSystem.textSecondary) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { saveRule() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || amountText.isEmpty)
                        .foregroundStyle(DesignSystem.primaryColor)
                }
            }
            .onAppear {
                loadInitialValuesIfNeeded()
            }
            .alert("保存失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好的") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func selectCategory(_ category: Category) {
        let target = category.name == category.rootCategoryName
            ? rootCategory(for: category.rootCategoryName) ?? category
            : category
        withAnimation(.spring(response: 0.3)) {
            selectedCategory = target
        }
        HapticManager.selection()
    }

    private func selectExactCategory(_ category: Category) {
        withAnimation(.spring(response: 0.3)) {
            selectedCategory = category
            wheelCategory = nil
            wheelSourceFrame = nil
        }
    }

    private func showWheel(for category: Category, sourceFrame: CGRect?) {
        let children = Category.childCategories(for: category.rootCategoryName, in: categories, isExpense: isExpense)
        guard !children.isEmpty else {
            selectCategory(category)
            return
        }
        wheelSourceFrame = sourceFrame
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82, blendDuration: 0.08)) {
            wheelCategory = category
        }
    }

    private func categoryWheel(for category: Category) -> some View {
        let rootName = category.rootCategoryName
        let children = Category.childCategories(for: rootName, in: categories, isExpense: isExpense)
        return CategoryWheelOverlay(
            parentCategory: rootCategory(for: rootName) ?? category,
            children: children,
            selectedCategory: selectedCategory,
            sourceFrame: wheelSourceFrame,
            onSelectParent: {
                if let root = rootCategory(for: rootName) {
                    selectExactCategory(root)
                } else {
                    selectExactCategory(category)
                }
            },
            onSelectChild: { child in
                selectExactCategory(child)
            },
            onDismiss: {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.9)) {
                    wheelCategory = nil
                    wheelSourceFrame = nil
                }
            }
        )
    }

    private func defaultCategory() -> Category? {
        guard let firstRoot = rootCategories.first else { return categories.first }
        return rootCategory(for: firstRoot.rootCategoryName) ?? firstRoot
    }

    private func rootCategory(for rootName: String) -> Category? {
        categories.first { $0.name == rootName && !$0.isArchived }
    }

    private func loadInitialValuesIfNeeded() {
        guard !didLoadInitialValues else { return }
        didLoadInitialValues = true

        if let editRule {
            title = editRule.title
            amountText = NSDecimalNumber(decimal: editRule.amount).stringValue
            frequency = editRule.frequency
            nextDueDate = editRule.nextDueDate
            if let existingEndDate = editRule.endDate {
                hasEndDate = true
                endDate = existingEndDate
            }
            selectedCategory = editRule.category
            selectedLedger = editRule.ledger
            isExpense = editRule.isExpense
        } else {
            selectedLedger = ledgers.first(where: { $0.isDefault }) ?? ledgers.first
        }
        selectedCategory = selectedCategory ?? defaultCategory()
    }

    private func saveRule() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = Decimal(string: amountText), amount > 0, !cleanTitle.isEmpty else { return }

        if let rule = editRule {
            rule.title = cleanTitle
            rule.amount = amount
            rule.isExpense = isExpense
            rule.frequency = frequency
            rule.nextDueDate = nextDueDate
            rule.endDate = hasEndDate ? endDate : nil
            rule.category = selectedCategory
            rule.ledger = selectedLedger
        } else {
            let rule = RecurringRule(
                title: cleanTitle,
                amount: amount,
                isExpense: isExpense,
                frequency: frequency,
                nextDueDate: nextDueDate,
                endDate: hasEndDate ? endDate : nil,
                category: selectedCategory,
                ledger: selectedLedger
            )
            modelContext.insert(rule)
        }

        if let error = safeSave(modelContext) {
            saveError = error
        } else {
            dismiss()
        }
    }
}
