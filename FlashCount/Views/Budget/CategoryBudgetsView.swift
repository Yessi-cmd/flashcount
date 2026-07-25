import SwiftUI
import SwiftData

struct CategoryBudgetsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("payday") private var payday = 1
    @AppStorage(WeekendBudgetPreferences.storageKey) private var weekendBudgetMultiplierPercent = WeekendBudgetPreferences.defaultRawValue
    @Query(sort: \Budget.createdAt) private var budgets: [Budget]
    @Query private var recentTransactions: [Transaction]
    @Query(
        filter: #Predicate<Category> { $0.isExpense == true },
        sort: \Category.sortOrder
    ) private var expenseCategories: [Category]

    @State private var showAddBudget = false
    @State private var editingBudget: Budget?
    @State private var saveError: String?

    init() {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: Date())) ?? .distantPast
        _recentTransactions = Query(
            filter: #Predicate<Transaction> { $0.date >= cutoff },
            sort: \Transaction.date,
            order: .reverse
        )
    }

    private var snapshots: [CategoryBudgetSnapshot] {
        CategoryBudgetService.snapshots(
            budgets: budgets,
            transactions: recentTransactions,
            categories: expenseCategories,
            ledger: nil,
            payday: payday,
            weekendMultiplier: WeekendBudgetPreferences.multiplier(for: weekendBudgetMultiplierPercent)
        )
    }

    var body: some View {
        List {
            Section {
                if snapshots.isEmpty {
                    emptyState
                } else {
                    ForEach(snapshots) { snapshot in
                        Button {
                            editingBudget = snapshot.budget
                        } label: {
                            CategoryBudgetRow(snapshot: snapshot)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("编辑\(snapshot.category.name)预算")
                        .accessibilityHint("双击调整预算")
                            .swipeActions {
                                Button(role: .destructive) {
                                    delete(snapshot.budget)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    editingBudget = snapshot.budget
                                } label: {
                                    Label("调整", systemImage: "slider.horizontal.3")
                                }
                                Button(role: .destructive) {
                                    delete(snapshot.budget)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                }
            } header: {
                Text(cycleTitle)
            } footer: {
                Text("一级分类预算会统计该分类下的全部子分类，并按发薪周期重新设置。")
            }
            .listRowBackground(DesignSystem.cardBackground)
        }
        .scrollContentBackground(.hidden)
        .background(DesignSystem.surfaceBackground)
        .navigationTitle("分类预算")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddBudget = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("添加分类预算")
                .accessibilityIdentifier("categoryBudgets.add")
            }
        }
        .sheet(isPresented: $showAddBudget) {
            CategoryBudgetEditorView(existingBudget: nil, payday: payday)
        }
        .sheet(item: $editingBudget) { budget in
            CategoryBudgetEditorView(existingBudget: budget, payday: payday)
        }
        .alert("保存失败", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 38))
                .foregroundStyle(DesignSystem.textTertiary)
            Text("还没有分类预算")
                .font(.headline)
                .foregroundStyle(DesignSystem.textPrimary)
            Text("为餐饮、购物等分类设置独立上限")
                .font(.subheadline)
                .foregroundStyle(DesignSystem.textSecondary)
            Button("添加分类预算") { showAddBudget = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.primaryColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private var cycleTitle: String {
        "当前发薪周期 · \(PayCycleService.cycle(payday: payday).displayTitle)"
    }

    private func delete(_ budget: Budget) {
        modelContext.delete(budget)
        if let error = safeSave(modelContext) {
            saveError = error
            HapticManager.error()
        }
    }
}

private struct CategoryBudgetRow: View {
    let snapshot: CategoryBudgetSnapshot

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: snapshot.category.icon)
                    .foregroundStyle(Color(hex: snapshot.category.colorHex))
                    .frame(width: 36, height: 36)
                    .background(Color(hex: snapshot.category.colorHex).opacity(0.12))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.category.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.textPrimary)
                    Text("已花 \(snapshot.analysis.totalSpent.formattedCurrency)")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(snapshot.analysis.budgetLimit.formattedCurrency)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(DesignSystem.textPrimary)
                    Text(alertTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(alertColor)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(DesignSystem.dividerColor)
                    Capsule()
                        .fill(alertColor)
                        .frame(width: proxy.size.width * min(max(snapshot.analysis.usagePercent, 0), 1))
                }
            }
            .frame(height: 7)

            HStack {
                Text("已用 \(Int(min(snapshot.analysis.usagePercent, 99.99) * 100))%")
                Spacer()
                Text(snapshot.analysis.remainingBudget >= 0
                     ? "剩余 \(snapshot.analysis.remainingBudget.formattedCurrency)"
                     : "超出 \((-snapshot.analysis.remainingBudget).formattedCurrency)")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(DesignSystem.textTertiary)
        }
        .padding(.vertical, 5)
    }

    private var alertTitle: String {
        switch snapshot.alertLevel {
        case .healthy: return "健康"
        case .warning: return "注意"
        case .danger: return "危险"
        }
    }

    private var alertColor: Color {
        switch snapshot.alertLevel {
        case .healthy: return DesignSystem.incomeColor
        case .warning: return DesignSystem.warningColor
        case .danger: return DesignSystem.dangerColor
        }
    }
}

private struct CategoryBudgetEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Budget.createdAt) private var budgets: [Budget]
    @Query(
        filter: #Predicate<Category> { $0.isExpense == true && $0.isArchived == false },
        sort: \Category.sortOrder
    ) private var categories: [Category]

    let existingBudget: Budget?
    let payday: Int

    @State private var selectedCategoryID: UUID?
    @State private var amountText = ""
    @State private var amountError: MoneyValidationError?
    @State private var didLoad = false
    @State private var saveError: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case amount
    }

    private var cycle: PayCycle { PayCycleService.cycle(payday: payday) }

    private var rootCategories: [Category] {
        let roots = Category.rootCategories(from: categories, isExpense: true)
        let occupied = Set(currentCycleBudgets.compactMap(\.categoryId))
        return roots.filter { category in
            category.id == existingBudget?.categoryId || !occupied.contains(category.id)
        }
    }

    private var currentCycleBudgets: [Budget] {
        CategoryBudgetService.currentBudgets(
            in: budgets,
            ledger: nil,
            payday: payday
        )
    }

    private var canSave: Bool {
        selectedCategoryID != nil && !amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("分类") {
                    if rootCategories.isEmpty {
                        Text("当前所有一级分类都已设置预算")
                            .foregroundStyle(DesignSystem.textSecondary)
                    } else {
                        Picker("一级分类", selection: $selectedCategoryID) {
                            Text("请选择").tag(nil as UUID?)
                            ForEach(rootCategories, id: \.id) { category in
                                Label(category.name, systemImage: category.icon)
                                    .tag(category.id as UUID?)
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        Text("¥")
                            .foregroundStyle(DesignSystem.textSecondary)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .focused($focusedField, equals: .amount)
                            .onChange(of: amountText) { _, _ in amountError = nil }
                        ValidationMessage(message: amountError?.errorDescription)
                    }
                    HStack {
                        ForEach(["500", "1000", "2000", "3000"], id: \.self) { amount in
                            Button("¥\(amount)") { amountText = amount }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("预算上限")
                } footer: {
                    Text("适用于 \(cycle.displayTitle)；下个发薪周期可以重新设置。")
                }
            }
            .navigationTitle(existingBudget == nil ? "添加分类预算" : "调整分类预算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear { loadIfNeeded() }
            .alert("保存失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        selectedCategoryID = existingBudget?.categoryId ?? rootCategories.first?.id
        if let existingBudget {
            amountText = NSDecimalNumber(decimal: existingBudget.monthlyLimit).stringValue
        }
    }

    private func save() {
        guard let categoryID = selectedCategoryID else { return }
        let amount: Decimal
        switch MoneyValidation.parse(amountText, requirement: .positive) {
        case .success(let value):
            amount = value
            amountError = nil
        case .failure(let error):
            amountError = error
            focusedField = .amount
            HapticManager.error()
            return
        }
        let year = Calendar.current.component(.year, from: cycle.start)
        let month = Calendar.current.component(.month, from: cycle.start)
        let duplicates = budgets.filter {
            $0.year == year && $0.month == month && $0.ledger == nil && $0.categoryId == categoryID
        }

        if let existingBudget {
            existingBudget.monthlyLimit = amount
            existingBudget.year = year
            existingBudget.month = month
            existingBudget.ledger = nil
            existingBudget.categoryId = categoryID
            for duplicate in duplicates where duplicate.id != existingBudget.id {
                modelContext.delete(duplicate)
            }
        } else if let newest = duplicates.max(by: { $0.createdAt < $1.createdAt }) {
            newest.monthlyLimit = amount
            for duplicate in duplicates where duplicate.id != newest.id {
                modelContext.delete(duplicate)
            }
        } else {
            modelContext.insert(Budget(
                monthlyLimit: amount,
                year: year,
                month: month,
                categoryId: categoryID
            ))
        }

        if let error = safeSave(modelContext) {
            saveError = error
        } else {
            HapticManager.success()
            dismiss()
        }
    }
}
