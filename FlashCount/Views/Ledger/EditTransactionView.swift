import SwiftUI
import SwiftData

/// 编辑交易记录
struct EditTransactionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Ledger.sortOrder) private var ledgers: [Ledger]
    @Query(
        filter: #Predicate<Category> { $0.isExpense == true && $0.isArchived == false },
        sort: \Category.sortOrder
    ) private var expenseCategories: [Category]
    @Query(
        filter: #Predicate<Category> { $0.isExpense == false && $0.isArchived == false },
        sort: \Category.sortOrder
    ) private var incomeCategories: [Category]

    @Bindable var transaction: Transaction

    @State private var amountText: String
    @State private var isExpense: Bool
    @State private var note: String
    @State private var selectedDate: Date
    @State private var selectedCategory: Category?
    @State private var selectedLedger: Ledger?
    @State private var saveError: String?
    @State private var wheelCategory: Category?
    @State private var showDeleteConfirm = false
    @State private var dailyBudgetOverride: Bool?

    init(transaction: Transaction) {
        self.transaction = transaction
        _amountText = State(initialValue: "\(transaction.amount)")
        _isExpense = State(initialValue: transaction.isExpense)
        _note = State(initialValue: transaction.note)
        _selectedDate = State(initialValue: transaction.date)
        _selectedCategory = State(initialValue: transaction.category)
        _selectedLedger = State(initialValue: transaction.ledger)
        _dailyBudgetOverride = State(initialValue: transaction.dailyBudgetOverride)
    }

    private var currentCategories: [Category] {
        isExpense ? expenseCategories : incomeCategories
    }

    private var rootCategories: [Category] {
        Category.rootCategories(from: currentCategories, isExpense: isExpense)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // 收支切换
                        HStack(spacing: 0) {
                            Button {
                                withAnimation(.spring(response: 0.3)) { isExpense = true }
                                selectedCategory = defaultCategory(from: expenseCategories, isExpense: true)
                                dailyBudgetOverride = nil
                            } label: {
                                Text("支出").font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(isExpense ? DesignSystem.expenseColor.opacity(0.2) : .clear)
                                    .foregroundStyle(isExpense ? DesignSystem.expenseColor : DesignSystem.textSecondary)
                            }
                            Button {
                                withAnimation(.spring(response: 0.3)) { isExpense = false }
                                selectedCategory = defaultCategory(from: incomeCategories, isExpense: false)
                                dailyBudgetOverride = nil
                            } label: {
                                Text("收入").font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(!isExpense ? DesignSystem.incomeColor.opacity(0.2) : .clear)
                                    .foregroundStyle(!isExpense ? DesignSystem.incomeColor : DesignSystem.textSecondary)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                        .overlay(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius).stroke(DesignSystem.borderColor, lineWidth: 1))

                        // 金额
                        VStack(alignment: .leading, spacing: 8) {
                            Text("金额").font(.caption.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
                            HStack {
                                Text("¥").font(.title3).foregroundStyle(DesignSystem.textSecondary)
                                TextField("0.00", text: $amountText)
                                    .keyboardType(.decimalPad)
                                    .font(.title2.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(DesignSystem.textPrimary)
                            }
                            .padding(12).background(DesignSystem.softFill)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                        }

                        // 分类
                        VStack(alignment: .leading, spacing: 8) {
                            Text("分类").font(.caption.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                                ForEach(rootCategories, id: \.id) { category in
                                    let children = Category.childCategories(for: category.rootCategoryName, in: currentCategories, isExpense: isExpense)
                                    CategorySelectionTile(
                                        category: category,
                                        selectedCategory: selectedCategory,
                                        hasChildren: !children.isEmpty,
                                        iconSize: .subheadline,
                                        circleSize: 44,
                                        minHeight: 74,
                                        onSelect: { selectCategory(category) },
                                        onLongPress: { showWheel(for: category) }
                                    )
                                }
                            }
                        }

                        // 备注
                        VStack(alignment: .leading, spacing: 8) {
                            Text("备注").font(.caption.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
                            TextField("添加备注...", text: $note).font(.subheadline).foregroundStyle(DesignSystem.textPrimary)
                                .padding(12).background(DesignSystem.softFill)
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                        }

                        // 日期
                        VStack(alignment: .leading, spacing: 8) {
                            Text("日期").font(.caption.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
                            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                                .datePickerStyle(.compact).labelsHidden()
                        }

                        if isExpense {
                            dailyBudgetOption
                        }

                        // 删除按钮
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "trash")
                                Text("删除此记录")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DesignSystem.dangerColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(DesignSystem.dangerColor.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius)
                                    .stroke(DesignSystem.dangerColor.opacity(0.2), lineWidth: 1)
                            )
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
            .alert("确认删除", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) { deleteTransaction() }
            } message: {
                Text("删除后无法恢复，确定要删除这笔交易吗？")
            }
            .navigationTitle("编辑记录").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }.foregroundStyle(DesignSystem.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if ledgers.count > 1 {
                            ledgerMenu
                        }

                        Button("保存") { saveChanges() }
                            .disabled(amountText.isEmpty)
                            .foregroundStyle(DesignSystem.primaryColor)
                    }
                }
            }
            .saveErrorAlert($saveError)
        }
    }

    private var ledgerMenu: some View {
        Menu {
            ForEach(ledgers, id: \.id) { ledger in
                Button {
                    selectedLedger = ledger
                    HapticManager.selection()
                } label: {
                    Label(ledger.name, systemImage: selectedLedger?.id == ledger.id ? "checkmark.circle.fill" : ledger.icon)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: selectedLedger?.icon ?? "book.closed")
                    .font(.caption)
                Text(selectedLedger?.name ?? "账本")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(DesignSystem.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(DesignSystem.softFill)
            .clipShape(Capsule())
        }
    }

    private var dailyBudgetOption: some View {
        HStack(spacing: 12) {
            Image(systemName: effectiveDailyBudgetValue ? "checkmark.circle.fill" : "minus.circle")
                .font(.subheadline)
                .foregroundStyle(effectiveDailyBudgetValue ? DesignSystem.primaryColor : DesignSystem.textTertiary)
                .frame(width: 30, height: 30)
                .background(DesignSystem.softFill)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("计入日常预算")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.textPrimary)
                Text(dailyBudgetOverride == nil ? "跟随所选分类的范围" : "仅覆盖这一笔支出")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.textTertiary)
            }

            Spacer(minLength: 6)

            if dailyBudgetOverride != nil {
                Button("恢复") {
                    dailyBudgetOverride = nil
                    HapticManager.selection()
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(DesignSystem.textSecondary)
            }

            Toggle("", isOn: Binding(
                get: { effectiveDailyBudgetValue },
                set: { value in
                    dailyBudgetOverride = value
                    HapticManager.selection()
                }
            ))
            .labelsHidden()
            .tint(DesignSystem.primaryColor)
        }
        .padding(12)
        .background(DesignSystem.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius, style: .continuous)
                .stroke(DesignSystem.borderColor, lineWidth: 1)
        }
    }

    private var effectiveDailyBudgetValue: Bool {
        dailyBudgetOverride ?? BudgetScope.includesCategory(selectedCategory)
    }

    private func selectCategory(_ category: Category) {
        let target = category.name == category.rootCategoryName
            ? rootCategory(for: category.rootCategoryName, in: currentCategories) ?? category
            : category
        withAnimation(.spring(response: 0.3)) {
            selectedCategory = target
            dailyBudgetOverride = nil
        }
        HapticManager.selection()
    }

    private func selectExactCategory(_ category: Category) {
        withAnimation(.spring(response: 0.3)) {
            selectedCategory = category
            dailyBudgetOverride = nil
            wheelCategory = nil
        }
    }

    private func showWheel(for category: Category) {
        let children = Category.childCategories(for: category.rootCategoryName, in: currentCategories, isExpense: isExpense)
        guard !children.isEmpty else {
            selectCategory(category)
            return
        }
        HapticManager.impact(.soft)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82, blendDuration: 0.08)) {
            wheelCategory = category
        }
    }

    private func categoryWheel(for category: Category) -> some View {
        let rootName = category.rootCategoryName
        let children = Category.childCategories(for: rootName, in: currentCategories, isExpense: isExpense)
        return CategoryWheelOverlay(
            parentCategory: rootCategory(for: rootName, in: currentCategories) ?? category,
            children: children,
            selectedCategory: selectedCategory,
            onSelectParent: {
                if let root = rootCategory(for: rootName, in: currentCategories) {
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
                }
            }
        )
    }

    private func defaultCategory(from categories: [Category], isExpense targetIsExpense: Bool) -> Category? {
        let roots = Category.rootCategories(from: categories, isExpense: targetIsExpense)
        guard let firstRoot = roots.first else { return categories.first }
        return rootCategory(for: firstRoot.rootCategoryName, in: categories) ?? firstRoot
    }

    private func rootCategory(for rootName: String, in categories: [Category]) -> Category? {
        categories.first { $0.name == rootName && !$0.isArchived }
    }

    private func saveChanges() {
        guard let amount = Decimal(string: amountText), amount > 0 else { return }
        let oldCashPoolDelta = transaction.cashPoolDelta
        transaction.amount = amount
        transaction.isExpense = isExpense
        transaction.note = note
        transaction.date = selectedDate
        transaction.category = selectedCategory
        transaction.ledger = selectedLedger
        transaction.isPrivateIncome = !isExpense && selectedCategory?.isSalaryIncome == true
        transaction.dailyBudgetOverride = isExpense ? dailyBudgetOverride : nil
        let newCashPoolDelta = CashPoolService.transactionDelta(for: transaction)
        transaction.cashPoolDelta = newCashPoolDelta
        CashPoolService(modelContext: modelContext).replace(oldDelta: oldCashPoolDelta, newDelta: newCashPoolDelta)

        if let error = safeSave(modelContext) {
            modelContext.rollback()
            saveError = error
            HapticManager.error()
            return
        }
        HapticManager.success()
        dismiss()
    }

    private func deleteTransaction() {
        CashPoolService(modelContext: modelContext).reverse(delta: transaction.cashPoolDelta)
        modelContext.delete(transaction)
        if let error = safeSave(modelContext) {
            modelContext.rollback()
            saveError = error
            HapticManager.error()
            return
        }
        HapticManager.success()
        dismiss()
    }
}
