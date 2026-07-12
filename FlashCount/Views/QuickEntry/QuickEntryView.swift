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
    @Query private var recentTransactions: [Transaction]

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
    @State private var wheelSourceFrame: CGRect?
    @State private var showAllCategories = false
    @State private var showTemplateManager = false
    @State private var editingTemplate: TransactionTemplate?
    @State private var isSaving = false
    @State private var dailyBudgetOverride: Bool?
    @Namespace private var typeSelectionNamespace

    init() {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: Date())) ?? .distantPast
        _recentTransactions = Query(
            filter: #Predicate<Transaction> { $0.date >= cutoff },
            sort: \Transaction.date,
            order: .reverse
        )
        _dailyBudgetOverride = State(initialValue: nil)
    }

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

        for transaction in recentTransactions where transaction.isExpense == isExpense {
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
                AmbientBackground(accent: isExpense ? DesignSystem.expenseColor : DesignSystem.incomeColor)
                    .animation(DesignSystem.standardAnimation, value: isExpense)

                ScrollView {
                    VStack(spacing: 8) {
                        // 收入/支出切换
                        typeToggle
                            .softReveal(delay: 0.02, distance: 8)

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
                        .softReveal(delay: 0.06, distance: 10)

                        // 金额显示
                        amountDisplay
                            .softReveal(delay: 0.10, distance: 12)

                        // 分类选择
                        categoryGrid
                            .softReveal(delay: 0.14, distance: 14)

                        // 备注
                        if showNote {
                            noteField
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: DesignSystem.space12) {
                        numberPad
                        submitButton
                    }
                    .padding(.horizontal)
                    .padding(.top, DesignSystem.space12)
                    .padding(.bottom, DesignSystem.space8)
                    .background(DesignSystem.cardBackground)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(DesignSystem.dividerColor)
                            .frame(height: 1)
                    }
                    .softReveal(delay: 0.18, distance: 18)
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
#if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains(where: { $0.hasPrefix("-visualCategoryMenuReview") }),
                   let reviewCategory = categoryMenuReviewCategory(arguments: arguments) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        wheelSourceFrame = nil
                        wheelCategory = reviewCategory
                    }
                }
#endif
            }
            .task(id: showSuccess) {
                guard showSuccess else { return }
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } catch {
                    return
                }
                guard showSuccess, !Task.isCancelled else { return }
                dismiss()
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
                    if let error = safeSave(modelContext) {
                        saveError = error
                    } else {
                        HapticManager.success()
                    }
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
                    .font(DesignSystem.Typography.compactLabel)
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
                dailyBudgetOverride = nil
                showAllCategories = false
                HapticManager.selection()
            } label: {
                Text("支出")
                    .font(DesignSystem.Typography.controlLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if isExpense {
                            RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius)
                                .fill(DesignSystem.expenseColor.opacity(0.18))
                                .matchedGeometryEffect(id: "quickEntryTypeSelection", in: typeSelectionNamespace)
                        }
                    }
                    .foregroundStyle(isExpense ? DesignSystem.expenseColor : DesignSystem.textSecondary)
            }

            Button {
                withAnimation(.spring(response: 0.3)) { isExpense = false }
                selectedCategory = defaultCategory(from: incomeCategories, isExpense: false)
                dailyBudgetOverride = nil
                showAllCategories = false
                HapticManager.selection()
            } label: {
                Text("收入")
                    .font(DesignSystem.Typography.controlLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if !isExpense {
                            RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius)
                                .fill(DesignSystem.incomeColor.opacity(0.18))
                                .matchedGeometryEffect(id: "quickEntryTypeSelection", in: typeSelectionNamespace)
                        }
                    }
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
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("¥")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(DesignSystem.textSecondary)
                Text(amountText.isEmpty ? "0.00" : amountText)
                    .font(DesignSystem.Typography.amount)
                    .monospacedDigit()
                    .foregroundStyle(DesignSystem.textPrimary)
                    .contentTransition(.numericText())
            }

            // 日期选择器 - 始终可见，方便补录历史账单
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.textSecondary)
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .scaleEffect(0.8)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            categorySection(title: "常用", categories: recentCategories)
            allCategoriesToggle

            if showAllCategories {
                categorySection(title: "全部分类", categories: rootCategories)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .glassCard()
    }

    private var allCategoriesToggle: some View {
        HStack(spacing: 8) {
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
                    .font(DesignSystem.Typography.compactLabel)
                    .foregroundStyle(DesignSystem.textSecondary)

                    Spacer(minLength: 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpense {
                Rectangle()
                    .fill(DesignSystem.dividerColor)
                    .frame(width: 1, height: 22)

                if dailyBudgetOverride != nil {
                    Button {
                        dailyBudgetOverride = nil
                        HapticManager.selection()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(DesignSystem.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("恢复跟随分类")
                }

                Text(dailyBudgetOverride == nil ? "日常预算" : "本笔覆盖")
                    .font(DesignSystem.Typography.supportingLabel)
                    .foregroundStyle(dailyBudgetOverride == nil ? DesignSystem.textSecondary : DesignSystem.primaryColor)
                    .lineLimit(1)

                Toggle("计入日常预算", isOn: dailyBudgetBinding)
                    .labelsHidden()
                    .tint(DesignSystem.primaryColor)
                    .scaleEffect(0.82)
                    .frame(width: 42)
            } else if let selectedCategory {
                Text(selectedCategory.entryDisplayName)
                    .font(DesignSystem.Typography.supportingLabel)
                    .foregroundStyle(DesignSystem.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(DesignSystem.softFill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func categorySection(title: String, categories: [Category]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(DesignSystem.Typography.compactLabelEmphasized)
                .foregroundStyle(DesignSystem.textTertiary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
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
            iconSize: .subheadline,
            circleSize: 36,
            minHeight: 62,
            onSelect: { _ in selectCategory(category) },
            onOpenChildren: { sourceFrame in
                showWheel(for: category, sourceFrame: sourceFrame)
            }
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

    private var effectiveDailyBudgetValue: Bool {
        dailyBudgetOverride ?? BudgetScope.includesCategory(selectedCategory)
    }

    private var dailyBudgetBinding: Binding<Bool> {
        Binding(
            get: { effectiveDailyBudgetValue },
            set: { value in
                dailyBudgetOverride = value
                HapticManager.selection()
            }
        )
    }

    private var numberPad: some View {
        QuickEntryNumberPad(onKeyPress: handleKeyPress)
    }

    private var submitButton: some View {
        QuickEntrySubmitButton(isEnabled: !amountText.isEmpty, isExpense: isExpense, action: saveTransaction)
    }

    private var successOverlay: some View {
        VStack(spacing: 16) {
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

            Divider()
                .frame(width: 160)

            Button {
                resetForm()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("再记一笔")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.primaryColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DesignSystem.primaryColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)

            Button {
                dismiss()
            } label: {
                Text("完成")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.textSecondary)
                    .underline()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.surfaceBackground.opacity(0.98))
        .transition(.scale(scale: 0.96).combined(with: .opacity))
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
        case "收入":
            withAnimation(.spring(response: 0.3)) { isExpense = false }
            selectedCategory = defaultCategory(from: incomeCategories, isExpense: false)
            dailyBudgetOverride = nil
            showAllCategories = false
        case "支出":
            withAnimation(.spring(response: 0.3)) { isExpense = true }
            selectedCategory = defaultCategory(from: expenseCategories, isExpense: true)
            dailyBudgetOverride = nil
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
            dailyBudgetOverride = nil
            showAllCategories = false
        }
        HapticManager.selection()
    }

    private func selectExactCategory(_ category: Category) {
        withAnimation(.spring(response: 0.3)) {
            selectedCategory = category
            dailyBudgetOverride = nil
            wheelCategory = nil
            wheelSourceFrame = nil
            showAllCategories = false
        }
    }

    private func showWheel(for category: Category, sourceFrame: CGRect?) {
        let children = Category.childCategories(for: category.rootCategoryName, in: currentCategories, isExpense: isExpense)
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
        let children = Category.childCategories(for: rootName, in: currentCategories, isExpense: isExpense)
        return CategoryWheelOverlay(
            parentCategory: rootCategory(for: rootName, in: currentCategories) ?? category,
            children: children,
            selectedCategory: selectedCategory,
            sourceFrame: wheelSourceFrame,
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
                    wheelSourceFrame = nil
                }
            }
        )
    }

#if DEBUG
    private func categoryMenuReviewCategory(arguments: [String]) -> Category? {
        let requestedName = arguments
            .first(where: { $0.hasPrefix("-visualCategoryMenuReview=") })?
            .split(separator: "=", maxSplits: 1)
            .last
            .map(String.init)

        if let requestedName,
           let requested = rootCategories.first(where: { $0.rootCategoryName == requestedName }) {
            return requested
        }
        return rootCategories.first
    }
#endif

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
        return recentTransactions.first { transaction in
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
            dailyBudgetOverride = nil
            showAllCategories = false
        }
        HapticManager.impact(.light)
    }

    private func saveTransaction() {
        guard !isSaving, let amount = Decimal(string: amountText), amount > 0 else { return }
        isSaving = true
        defer { isSaving = false }

        let transaction = Transaction(
            amount: amount,
            isExpense: isExpense,
            note: note,
            date: selectedDate,
            isPrivateIncome: !isExpense && selectedCategory?.isSalaryIncome == true,
            dailyBudgetOverride: isExpense ? dailyBudgetOverride : nil,
            category: selectedCategory,
            ledger: selectedLedger
        )
        let cashDelta = CashPoolService.transactionDelta(for: transaction)
        transaction.cashPoolDelta = cashDelta
        modelContext.insert(transaction)
        CashPoolService(modelContext: modelContext).apply(delta: cashDelta)

        if let error = safeSave(modelContext) {
            modelContext.rollback()
            saveError = error
            HapticManager.error()
            return
        }

        HapticManager.success()
        updateBudgetReminder(afterSaving: transaction)

        withAnimation(.spring(response: 0.4)) {
            showSuccess = true
        }
    }

    private func resetForm() {
        withAnimation(.spring(response: 0.3)) {
            amountText = ""
            note = ""
            showNote = false
            showSuccess = false
            budgetReminderText = nil
            budgetReminderLevel = nil
            dailyBudgetOverride = nil
        }
    }

    private func updateBudgetReminder(afterSaving transaction: Transaction) {
        budgetReminderText = nil
        budgetReminderLevel = nil
        guard transaction.isExpense else { return }

        let cycle = PayCycleService.cycle(containing: transaction.date, payday: payday)
        let cycleStart = cycle.start
        let cycleEnd = cycle.end
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { item in
                item.date >= cycleStart && item.date < cycleEnd
            },
            sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
        )

        let transactions: [Transaction]
        do {
            transactions = try modelContext.fetch(descriptor)
        } catch {
            return
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
