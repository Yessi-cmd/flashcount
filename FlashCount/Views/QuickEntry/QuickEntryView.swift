import SwiftUI
import SwiftData

/// 极速记账页面 - 打开即可记账，3秒完成
struct QuickEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("payday") private var payday = 1

    @Query(sort: \Ledger.sortOrder) private var ledgers: [Ledger]
    @Query(
        filter: #Predicate<Category> { $0.isExpense == true && $0.isArchived == false },
        sort: \Category.sortOrder
    ) private var expenseCategories: [Category]
    @Query(
        filter: #Predicate<Category> { $0.isExpense == false && $0.isArchived == false },
        sort: \Category.sortOrder
    ) private var incomeCategories: [Category]
    @Query(sort: \Budget.createdAt) private var allBudgets: [Budget]
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]

    @State private var amountText = ""
    @State private var isExpense = true
    @State private var selectedCategory: Category?
    @State private var selectedLedger: Ledger?
    @State private var note = ""
    @State private var selectedDate = Date()
    @State private var showDatePicker = false
    @State private var showSuccess = false
    @State private var showNote = false
    @State private var saveError: String?
    @State private var budgetReminderText: String?
    @State private var budgetReminderLevel: BudgetAlertLevel?
    @State private var wheelCategory: Category?
    @State private var showAllCategories = false
    @State private var showTemplateManager = false
    @State private var editingTemplate: TransactionTemplate?

    private var currentCategories: [Category] {
        isExpense ? expenseCategories : incomeCategories
    }

    private var rootCategories: [Category] {
        Category.rootCategories(from: currentCategories, isExpense: isExpense)
    }

    private var recentCategories: [Category] {
        var seen = Set<String>()
        var result: [Category] = []
        let rootNames = Set(rootCategories.map(\.rootCategoryName))

        for transaction in allTransactions where transaction.isExpense == isExpense {
            guard let category = transaction.category else { continue }
            let rootName = category.rootCategoryName
            guard rootNames.contains(rootName), !seen.contains(rootName), let representative = categoryRepresentative(for: rootName) else { continue }
            result.append(representative)
            seen.insert(rootName)
            if result.count >= 8 { break }
        }

        return result.isEmpty ? Array(rootCategories.prefix(8)) : result
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                DesignSystem.surfaceBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // 收入/支出切换
                        typeToggle

                        // 记账模板
                        TemplateBarView(
                            expenseCategories: expenseCategories,
                            incomeCategories: incomeCategories,
                            onSelect: { template, category in
                                applyTemplate(template, category: category)
                            },
                            onManage: { showTemplateManager = true },
                            onEditTemplate: { template in
                                editingTemplate = template
                            }
                        )

                        // 金额显示
                        amountDisplay

                        // 分类选择
                        categoryGrid

                        // 备注 & 日期
                        if showNote {
                            noteField
                        }

                        // 数字键盘
                        numberPad

                        // 提交按钮
                        submitButton
                    }
                    .padding()
                }
            }
            .navigationTitle("记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(DesignSystem.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if ledgers.count > 1 {
                            ledgerMenu
                        }

                        Button {
                            showNote.toggle()
                        } label: {
                            Image(systemName: "note.text")
                                .foregroundStyle(showNote ? DesignSystem.primaryColor : DesignSystem.textSecondary)
                        }
                    }
                }
            }
            .overlay {
                if let wheelCategory {
                    categoryWheel(for: wheelCategory)
                }
            }
            .overlay {
                if showSuccess {
                    successOverlay
                }
            }
            .onAppear {
                // 默认选中默认账本
                if selectedLedger == nil {
                    selectedLedger = ledgers.first(where: { $0.isDefault }) ?? ledgers.first
                }
                // 默认选中第一个分类
                if selectedCategory == nil {
                    selectedCategory = defaultCategory(from: currentCategories, isExpense: isExpense)
                }
            }
            .saveErrorAlert($saveError)
            .sheet(isPresented: $showTemplateManager) {
                TemplateManagementView()
            }
            .sheet(item: $editingTemplate) { template in
                TemplateEditView(
                    categories: expenseCategories + incomeCategories,
                    template: template
                ) { _ in
                    try? modelContext.save()
                    HapticManager.success()
                }
            }
        }
    }

    // MARK: - Components

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

    private var typeToggle: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3)) { isExpense = true }
                selectedCategory = defaultCategory(from: expenseCategories, isExpense: true)
                showAllCategories = false
            } label: {
                Text("支出")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isExpense ? DesignSystem.expenseColor.opacity(0.2) : .clear)
                    .foregroundStyle(isExpense ? DesignSystem.expenseColor : DesignSystem.textSecondary)
            }

            Button {
                withAnimation(.spring(response: 0.3)) { isExpense = false }
                selectedCategory = defaultCategory(from: incomeCategories, isExpense: false)
                showAllCategories = false
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
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius)
                .stroke(DesignSystem.borderColor, lineWidth: 1)
        )
    }

    private var amountDisplay: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("¥")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(DesignSystem.textSecondary)
                Text(amountText.isEmpty ? "0.00" : amountText)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(DesignSystem.textPrimary)
                    .contentTransition(.numericText())
            }

            // 日期选择器 - 始终可见，方便补录历史账单
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textSecondary)
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .scaleEffect(0.85)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            categorySection(title: "常用 / 最近", categories: recentCategories)
            allCategoriesToggle

            if showAllCategories {
                categorySection(title: "全部分类", categories: rootCategories)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .glassCard()
    }

    private var allCategoriesToggle: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                showAllCategories.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: showAllCategories ? "chevron.up.circle.fill" : "square.grid.2x2")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.primaryColor)

                Text(showAllCategories ? "收起全部分类" : "展开全部分类")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DesignSystem.textSecondary)

                Spacer(minLength: 8)

                if let selectedCategory {
                    Text(selectedCategory.entryDisplayName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(DesignSystem.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DesignSystem.softFill)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func categorySection(title: String, categories: [Category]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(DesignSystem.textTertiary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                ForEach(categories, id: \.id) { category in
                    categoryButton(category)
                }
            }
        }
    }

    private func categoryButton(_ category: Category) -> some View {
        let children = Category.childCategories(for: category.rootCategoryName, in: currentCategories, isExpense: isExpense)
        return CategorySelectionTile(
            category: category,
            selectedCategory: selectedCategory,
            hasChildren: !children.isEmpty,
            iconSize: .title3,
            circleSize: 46,
            minHeight: 70,
            onSelect: { selectCategory(category) },
            onLongPress: { showWheel(for: category) }
        )
    }

    private var noteField: some View {
        HStack {
            Image(systemName: "pencil")
                .foregroundStyle(DesignSystem.textTertiary)
            TextField("添加备注...", text: $note)
                .foregroundStyle(DesignSystem.textPrimary)
                .font(.subheadline)
        }
        .padding(12)
        .background(DesignSystem.softFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var numberPad: some View {
        let buttons = [
            ["7", "8", "9", "⌫"],
            ["4", "5", "6", "+"],
            ["1", "2", "3", "-"],
            [".", "0", "00", ""]
        ]

        return VStack(spacing: 8) {
            ForEach(buttons, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { button in
                        if button.isEmpty {
                            Color.clear.frame(height: 50)
                        } else {
                            Button {
                                handleKeyPress(button)
                            } label: {
                                Text(button)
                                    .font(.title3.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(DesignSystem.softFill)
                                    .foregroundStyle(
                                        button == "⌫" ? DesignSystem.textSecondary
                                        : button == "+" ? DesignSystem.incomeColor
                                        : button == "-" ? DesignSystem.expenseColor
                                        : DesignSystem.textPrimary
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
            }
        }
    }

    private var submitButton: some View {
        Button {
            saveTransaction()
        } label: {
            Text("保存")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    amountText.isEmpty
                    ? AnyShapeStyle(.gray.opacity(0.3))
                    : isExpense
                        ? AnyShapeStyle(DesignSystem.expenseGradient)
                        : AnyShapeStyle(DesignSystem.incomeGradient)
                )
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        }
        .disabled(amountText.isEmpty)
    }

    private var successOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(DesignSystem.incomeColor)
                .symbolEffect(.bounce, value: showSuccess)

            Text("记账成功！")
                .font(.headline)
                .foregroundStyle(DesignSystem.textPrimary)
            if let budgetReminderText {
                HStack(spacing: 6) {
                    Image(systemName: budgetReminderIcon)
                    Text(budgetReminderText)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(budgetReminderColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(budgetReminderColor.opacity(0.12))
                .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .transition(.opacity)
    }

    // MARK: - Logic

    private func handleKeyPress(_ key: String) {
        let maxIntegerDigits = 12  // 最大整数位数（万亿级别）

        switch key {
        case "⌫":
            if !amountText.isEmpty {
                amountText.removeLast()
            }
        case ".":
            if !amountText.contains(".") {
                amountText += amountText.isEmpty ? "0." : "."
            }
        case "00":
            let intPart = amountText.split(separator: ".").first.map(String.init) ?? amountText
            if intPart.count >= maxIntegerDigits { return }
            if !amountText.isEmpty && !amountText.contains(".") {
                amountText += "00"
            } else if amountText.contains(".") {
                let parts = amountText.split(separator: ".")
                if parts.count < 2 || parts[1].count < 2 {
                    amountText += "0"
                }
            }
        case "+":
            withAnimation(.spring(response: 0.3)) { isExpense = false }
            selectedCategory = defaultCategory(from: incomeCategories, isExpense: false)
            showAllCategories = false
        case "-":
            withAnimation(.spring(response: 0.3)) { isExpense = true }
            selectedCategory = defaultCategory(from: expenseCategories, isExpense: true)
            showAllCategories = false
        default:
            // 限制整数部分最多 12 位
            let intPart = amountText.split(separator: ".").first.map(String.init) ?? amountText
            if !amountText.contains(".") && intPart.count >= maxIntegerDigits { return }
            // 限制小数点后两位
            if amountText.contains(".") {
                let parts = amountText.split(separator: ".")
                if parts.count >= 2 && parts[1].count >= 2 {
                    return
                }
            }
            amountText += key
        }
    }

    private func selectCategory(_ category: Category) {
        let rootName = category.rootCategoryName
        let target = category.name == rootName
            ? lastUsedCategory(for: rootName, in: currentCategories, isExpense: isExpense) ?? rootCategory(for: rootName, in: currentCategories) ?? category
            : category

        withAnimation(.spring(response: 0.3)) {
            selectedCategory = target
            showAllCategories = false
        }
        HapticManager.selection()
    }

    private func selectExactCategory(_ category: Category) {
        withAnimation(.spring(response: 0.3)) {
            selectedCategory = category
            wheelCategory = nil
            showAllCategories = false
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
        return lastUsedCategory(for: firstRoot.rootCategoryName, in: categories, isExpense: targetIsExpense)
            ?? rootCategory(for: firstRoot.rootCategoryName, in: categories)
            ?? firstRoot
    }

    private func categoryRepresentative(for rootName: String) -> Category? {
        rootCategory(for: rootName, in: currentCategories)
            ?? currentCategories.first { $0.rootCategoryName == rootName }
    }

    private func rootCategory(for rootName: String, in categories: [Category]) -> Category? {
        categories.first { $0.name == rootName && !$0.isArchived }
    }

    private func lastUsedCategory(for rootName: String, in categories: [Category], isExpense targetIsExpense: Bool) -> Category? {
        let categoryIDs = Set(categories.map(\.id))
        return allTransactions.first { transaction in
            guard transaction.isExpense == targetIsExpense, let category = transaction.category else { return false }
            return categoryIDs.contains(category.id) && category.rootCategoryName == rootName
        }?.category
    }

    /// 应用模板 — 一键填入金额 / 分类 / 备注 / 收支类型
    private func applyTemplate(_ template: TransactionTemplate, category: Category?) {
        withAnimation(.spring(response: 0.3)) {
            amountText = String(describing: template.amount)
            isExpense = template.isExpense
            note = template.note
            selectedCategory = category
            showAllCategories = false
        }
        HapticManager.impact(.light)
    }

    private func saveTransaction() {
        guard let amount = Decimal(string: amountText), amount > 0 else { return }

        let transaction = Transaction(
            amount: amount,
            isExpense: isExpense,
            note: note,
            date: selectedDate,
            isPrivateIncome: !isExpense && selectedCategory?.isSalaryIncome == true,
            category: selectedCategory,
            ledger: selectedLedger
        )
        let cashDelta = CashPoolService.transactionDelta(for: transaction)
        transaction.cashPoolDelta = cashDelta
        modelContext.insert(transaction)
        CashPoolService(modelContext: modelContext).apply(delta: cashDelta)

        if let error = safeSave(modelContext) {
            saveError = error
            HapticManager.error()
            return
        }

        HapticManager.success()
        updateBudgetReminder(afterSaving: transaction)

        // 成功动画
        withAnimation(.spring(response: 0.4)) {
            showSuccess = true
        }

        let delay = budgetReminderText == nil ? 1.0 : 1.6
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            dismiss()
        }
    }

    private func updateBudgetReminder(afterSaving transaction: Transaction) {
        budgetReminderText = nil
        budgetReminderLevel = nil
        guard transaction.isExpense else { return }

        var transactions = allTransactions
        if !transactions.contains(where: { $0.id == transaction.id }) {
            transactions.insert(transaction, at: 0)
        }

        guard let reminder = BudgetReminderService.reminder(
            budgets: allBudgets,
            transactions: transactions,
            ledger: nil,
            referenceDate: transaction.date,
            payday: payday
        ), reminder.shouldSurfaceAfterSave else { return }

        budgetReminderText = reminder.shortMessage
        budgetReminderLevel = reminder.alertLevel
    }

    private var budgetReminderIcon: String {
        switch budgetReminderLevel {
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "flame.fill"
        default: return "checkmark.circle.fill"
        }
    }

    private var budgetReminderColor: Color {
        switch budgetReminderLevel {
        case .warning: return DesignSystem.warningColor
        case .danger: return DesignSystem.dangerColor
        default: return DesignSystem.incomeColor
        }
    }
}
