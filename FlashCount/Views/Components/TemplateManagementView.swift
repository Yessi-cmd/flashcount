import SwiftUI
import SwiftData

/// 记账模板管理页面
struct TemplateManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \TransactionTemplate.sortOrder) private var templates: [TransactionTemplate]
    @Query(
        filter: #Predicate<Category> { !$0.isArchived },
        sort: \Category.sortOrder
    ) private var allCategories: [Category]

    @State private var showAddSheet = false
    @State private var editingTemplate: TransactionTemplate?
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()

                if templates.isEmpty {
                    emptyState
                } else {
                    templateList
                }
            }
            .navigationTitle("记账模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(DesignSystem.primaryColor)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        EditButton()
                            .foregroundStyle(DesignSystem.primaryColor)
                        Button {
                            showAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(DesignSystem.primaryColor)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("添加记账模板")
                        .accessibilityIdentifier("templates.add")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                TemplateEditView(categories: allCategories) { template in
                    modelContext.insert(template)
                    if let error = safeSave(modelContext) {
                        saveError = error
                    } else {
                        HapticManager.success()
                    }
                }
            }
            .sheet(item: $editingTemplate) { template in
                TemplateEditView(categories: allCategories, template: template) { updated in
                    // 原地更新已在 Bindable 中完成
                    if let error = safeSave(modelContext) {
                        saveError = error
                    } else {
                        HapticManager.success()
                    }
                }
            }
            .saveErrorAlert($saveError)
        }
    }

    private var templateList: some View {
        List {
            ForEach(templates, id: \.id) { template in
                Button {
                    editingTemplate = template
                } label: {
                    templateRow(template)
                }
                .listRowBackground(DesignSystem.cardBackground)
            }
            .onDelete { indexSet in
                for index in indexSet {
                    modelContext.delete(templates[index])
                }
                if let error = safeSave(modelContext) {
                    saveError = error
                }
            }
            .onMove { from, to in
                var sorted = templates
                sorted.move(fromOffsets: from, toOffset: to)
                for (index, t) in sorted.enumerated() {
                    t.sortOrder = index
                }
                if let error = safeSave(modelContext) {
                    saveError = error
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func templateRow(_ template: TransactionTemplate) -> some View {
        HStack(spacing: 12) {
            // 左侧图标
            ZStack {
                Circle()
                    .fill(
                        template.isExpense
                        ? DesignSystem.expenseColor.opacity(0.12)
                        : DesignSystem.incomeColor.opacity(0.12)
                    )
                    .frame(width: 40, height: 40)
                Image(systemName: template.isExpense ? "arrow.up.right" : "arrow.down.left")
                    .font(.subheadline)
                    .foregroundStyle(
                        template.isExpense
                        ? DesignSystem.expenseColor
                        : DesignSystem.incomeColor
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.textPrimary)
                HStack(spacing: 4) {
                    Text(template.isExpense ? "支出" : "收入")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.textTertiary)
                    if let catName = template.categoryName {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(DesignSystem.textTertiary)
                        Text(catName)
                            .font(.caption2)
                            .foregroundStyle(DesignSystem.textTertiary)
                    }
                    if !template.note.isEmpty {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(DesignSystem.textTertiary)
                        Text(template.note)
                            .font(.caption2)
                            .foregroundStyle(DesignSystem.textTertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Text(template.amount.formattedAmount)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(
                    template.isExpense
                    ? DesignSystem.expenseColor
                    : DesignSystem.incomeColor
                )
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.square.fill")
                .font(.system(size: 40))
                .foregroundStyle(DesignSystem.textTertiary)
            Text("还没有记账模板")
                .font(.subheadline)
                .foregroundStyle(DesignSystem.textTertiary)
            Text("添加模板后可在记账页一键填入金额和分类")
                .font(.caption)
                .foregroundStyle(DesignSystem.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showAddSheet = true
            } label: {
                Text("添加模板")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.primaryColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 模板编辑 / 新建

struct TemplateEditView: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [Category]
    var template: TransactionTemplate?

    let onSave: (TransactionTemplate) -> Void

    @State private var name: String
    @State private var amountText: String
    @State private var isExpense: Bool
    @State private var note: String
    @State private var selectedCategoryName: String?
    @State private var nameError: String?
    @State private var amountError: MoneyValidationError?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case amount
    }

    init(categories: [Category], template: TransactionTemplate? = nil, onSave: @escaping (TransactionTemplate) -> Void) {
        self.categories = categories
        self.template = template
        self.onSave = onSave
        _name = State(initialValue: template?.name ?? "")
        _amountText = State(initialValue: template.map { "\($0.amount)" } ?? "")
        _isExpense = State(initialValue: template?.isExpense ?? true)
        _note = State(initialValue: template?.note ?? "")
        _selectedCategoryName = State(initialValue: template?.categoryName)
    }

    private var expenseCategories: [Category] {
        Category.rootCategories(from: categories, isExpense: true)
    }

    private var incomeCategories: [Category] {
        Category.rootCategories(from: categories, isExpense: false)
    }

    private var canSave: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && !amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("模板名称", text: $name)
                        .foregroundStyle(DesignSystem.textPrimary)
                    if let nameError {
                        Text(nameError)
                            .font(.caption)
                            .foregroundStyle(DesignSystem.dangerColor)
                    }
                } header: {
                    Text("名称").foregroundStyle(DesignSystem.textSecondary)
                }

                Section {
                    HStack {
                        Text("¥")
                            .foregroundStyle(DesignSystem.textTertiary)
                        TextField("金额", text: $amountText)
                            .keyboardType(.decimalPad)
                            .foregroundStyle(DesignSystem.textPrimary)
                            .focused($focusedField, equals: .amount)
                            .onChange(of: amountText) { _, _ in amountError = nil }
                        ValidationMessage(message: amountError?.errorDescription)
                    }
                } header: {
                    Text("金额").foregroundStyle(DesignSystem.textSecondary)
                }

                Section {
                    Picker("类型", selection: $isExpense) {
                        Text("支出").tag(true)
                        Text("收入").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: isExpense) { _, _ in
                        if let catName = selectedCategoryName {
                            let pool = isExpense ? expenseCategories : incomeCategories
                            if !pool.contains(where: { $0.name == catName || $0.rootCategoryName == catName }) {
                                selectedCategoryName = nil
                            }
                        }
                    }
                } header: {
                    Text("交易类型").foregroundStyle(DesignSystem.textSecondary)
                }

                Section {
                    if let selected = selectedCategoryName {
                        HStack {
                            Text("已选")
                            Spacer()
                            Text(selected)
                                .foregroundStyle(DesignSystem.textSecondary)
                            Button("清除") { selectedCategoryName = nil }
                                .font(.caption)
                                .foregroundStyle(DesignSystem.primaryColor)
                        }
                    }
                    let pool = isExpense ? expenseCategories : incomeCategories
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(pool, id: \.id) { cat in
                                Button {
                                    selectedCategoryName = cat.name
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: cat.icon)
                                            .font(.caption)
                                        Text(cat.name)
                                            .font(.caption.weight(.medium))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        selectedCategoryName == cat.name
                                        ? Color(hex: cat.colorHex).opacity(0.2)
                                        : DesignSystem.softFill
                                    )
                                    .foregroundStyle(
                                        selectedCategoryName == cat.name
                                        ? Color(hex: cat.colorHex)
                                        : DesignSystem.textSecondary
                                    )
                                    .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("分类").foregroundStyle(DesignSystem.textSecondary)
                }

                Section {
                    TextField("预设备注（可选）", text: $note)
                        .foregroundStyle(DesignSystem.textPrimary)
                } header: {
                    Text("备注").foregroundStyle(DesignSystem.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignSystem.surfaceBackground)
            .navigationTitle(template == nil ? "新建模板" : "编辑模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(DesignSystem.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                        .foregroundStyle(DesignSystem.primaryColor)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            nameError = "名称不能为空"
            return
        }
        let amount: Decimal
        switch MoneyValidation.parse(amountText, requirement: .positive) {
        case .success(let value):
            amount = value
            amountError = nil
        case .failure(let error):
            amountError = error
            focusedField = .amount
            return
        }

        if let existing = template {
            existing.name = trimmedName
            existing.amount = amount
            existing.isExpense = isExpense
            existing.note = note
            existing.categoryName = selectedCategoryName
            onSave(existing)
        } else {
            let newTemplate = TransactionTemplate(
                name: trimmedName,
                amount: amount,
                isExpense: isExpense,
                note: note,
                categoryName: selectedCategoryName,
                sortOrder: 0
            )
            onSave(newTemplate)
        }
        dismiss()
    }
}
