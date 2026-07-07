import SwiftUI
import SwiftData

/// 账本主页面 - 展示当前账本的交易列表和统计
struct LedgerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var privacyLock: PrivacyLockService
    @AppStorage("payday") private var payday = 1
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \Budget.createdAt) private var allBudgets: [Budget]

    @Query(
        filter: #Predicate<Category> { !$0.isArchived },
        sort: \Category.sortOrder
    ) private var allCategories: [Category]

    @State private var showAddTransaction = false
    @State private var editingTransaction: Transaction?
    @State private var searchText = ""
    @State private var dateFilter: DateFilter = .all
    @State private var showCalendar = false
    @State private var showSettings = false
    @State private var showReminders = false
    @State private var customStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    @State private var customEndDate = Date()

    // 高级筛选状态
    @State private var showFilterSheet = false
    @State private var typeFilter: TransactionTypeFilter = .all
    @State private var categoryFilterId: UUID?
    @State private var minAmountText = ""
    @State private var maxAmountText = ""

    enum DateFilter: String, CaseIterable {
        case all = "全部"
        case today = "今天"
        case thisWeek = "本周"
        case thisMonth = "本月"
        case custom = "自定义"
    }

    private var filteredTransactions: [Transaction] {
        var result = allTransactions
        // 日期筛选
        let calendar = Calendar.current
        let now = Date()
        switch dateFilter {
        case .all: break
        case .today:
            let start = calendar.startOfDay(for: now)
            result = result.filter { $0.date >= start }
        case .thisWeek:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            result = result.filter { $0.date >= start }
        case .thisMonth:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
            result = result.filter { $0.date >= start }
        case .custom:
            let start = calendar.startOfDay(for: customStartDate)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEndDate))!
            result = result.filter { $0.date >= start && $0.date < end }
        }
        // 类型筛选
        if typeFilter != .all {
            let isExpenseSelected = typeFilter == .expense
            result = result.filter { $0.isExpense == isExpenseSelected }
        }

        // 分类筛选
        if let categoryId = categoryFilterId,
           let category = allCategories.first(where: { $0.id == categoryId }) {
            if category.rootCategoryName == category.name {
                // 根分类：匹配所有该根分类下的交易
                result = result.filter { $0.category?.rootCategoryName == category.name }
            } else {
                // 子分类：精确匹配
                result = result.filter { $0.category?.id == categoryId }
            }
        }

        // 金额范围筛选
        if let minVal = Decimal(string: minAmountText), minVal > 0 {
            result = result.filter { $0.amount >= minVal }
        }
        if let maxVal = Decimal(string: maxAmountText), maxVal > 0 {
            result = result.filter { $0.amount <= maxVal }
        }

        // 关键词搜索
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                if isPrivateIncomeHidden($0) { return false }
                return $0.note.lowercased().contains(query) ||
                $0.category?.name.lowercased().contains(query) == true ||
                $0.category?.rootCategoryName.lowercased().contains(query) == true ||
                "\($0.amount)".contains(query)
            }
        }
        return result
    }

    private var monthlyExpense: Decimal {
        let calendar = Calendar.current
        let now = Date()
        return filteredTransactions
            .filter { $0.isExpense && calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    private var monthlyIncome: Decimal {
        let calendar = Calendar.current
        let now = Date()
        return filteredTransactions
            .filter { !$0.isExpense && !isPrivateIncomeHidden($0) && calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    private var hasHiddenMonthlyIncome: Bool {
        let calendar = Calendar.current
        let now = Date()
        return filteredTransactions.contains {
            isPrivateIncomeHidden($0) && calendar.isDate($0.date, equalTo: now, toGranularity: .month)
        }
    }

    private var budgetReminder: BudgetReminder? {
        BudgetReminderService.reminder(
            budgets: allBudgets,
            transactions: allTransactions,
            ledger: nil,
            payday: payday
        )
    }

    /// 按日期分组的交易
    private var groupedTransactions: [(String, [Transaction])] {
        let grouped = Dictionary(grouping: filteredTransactions) { transaction -> String in
            transaction.date.relativeString
        }
        return grouped.sorted { a, b in
            let dateA = a.value.first?.date ?? Date()
            let dateB = b.value.first?.date ?? Date()
            return dateA > dateB
        }
    }

    /// 是否有活跃的筛选条件（不计关键词搜索）
    private var hasActiveFilters: Bool {
        typeFilter != .all
        || categoryFilterId != nil
        || (!minAmountText.isEmpty && (Decimal(string: minAmountText) ?? 0) > 0)
        || (!maxAmountText.isEmpty && (Decimal(string: maxAmountText) ?? 0) > 0)
    }

    /// 活跃筛选条件数量（不计关键词搜索）
    private var activeFilterCount: Int {
        var count = 0
        if typeFilter != .all { count += 1 }
        if categoryFilterId != nil { count += 1 }
        if !minAmountText.isEmpty && (Decimal(string: minAmountText) ?? 0) > 0 { count += 1 }
        if !maxAmountText.isEmpty && (Decimal(string: maxAmountText) ?? 0) > 0 { count += 1 }
        return count
    }

    private func isPrivateIncomeHidden(_ transaction: Transaction) -> Bool {
        transaction.isProtectedIncome && !privacyLock.isUnlocked
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DesignSystem.sectionSpacing) {
                        // 搜索栏
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.subheadline)
                                .foregroundStyle(DesignSystem.textTertiary)
                            TextField("搜索备注、分类、金额...", text: $searchText)
                                .font(.subheadline)
                                .foregroundStyle(DesignSystem.textPrimary)
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(DesignSystem.textTertiary)
                                }
                            }
                        }
                        .padding(10)
                        .background(DesignSystem.softFill)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        // 活跃筛选条件标签
                        if hasActiveFilters {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    if typeFilter != .all {
                                        FilterChip(
                                            label: typeFilter.rawValue,
                                            color: typeFilter == .expense ? DesignSystem.expenseColor : DesignSystem.incomeColor
                                        ) { typeFilter = .all }
                                    }
                                    if let id = categoryFilterId,
                                       let cat = allCategories.first(where: { $0.id == id }) {
                                        FilterChip(
                                            label: cat.name,
                                            color: Color(hex: cat.colorHex)
                                        ) { categoryFilterId = nil }
                                    }
                                    if let minVal = Decimal(string: minAmountText), minVal > 0 {
                                        FilterChip(
                                            label: "¥\(minVal.formattedAmount)以上",
                                            color: DesignSystem.primaryColor
                                        ) { minAmountText = "" }
                                    }
                                    if let maxVal = Decimal(string: maxAmountText), maxVal > 0 {
                                        FilterChip(
                                            label: "¥\(maxVal.formattedAmount)以下",
                                            color: DesignSystem.primaryColor
                                        ) { maxAmountText = "" }
                                    }
                                    Button {
                                        withAnimation(.spring(response: 0.3)) {
                                            typeFilter = .all
                                            categoryFilterId = nil
                                            minAmountText = ""
                                            maxAmountText = ""
                                        }
                                        HapticManager.selection()
                                    } label: {
                                        Text("清除全部")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(DesignSystem.textTertiary)
                                    }
                                }
                            }
                        }

                        // 日期筛选快捷标签
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(DateFilter.allCases, id: \.self) { filter in
                                    Button {
                                        withAnimation(.spring(response: 0.3)) { dateFilter = filter }
                                    } label: {
                                        Text(filter.rawValue)
                                            .font(.caption.weight(.medium))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(dateFilter == filter ? DesignSystem.primaryColor.opacity(0.16) : DesignSystem.softFill)
                                            .foregroundStyle(dateFilter == filter ? DesignSystem.primaryColor : DesignSystem.textSecondary)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }

                        // 自定义日期范围
                        if dateFilter == .custom {
                            HStack(spacing: 12) {
                                DatePicker("", selection: $customStartDate, displayedComponents: .date)
                                    .datePickerStyle(.compact).labelsHidden()
                                Text("→").foregroundStyle(DesignSystem.textTertiary)
                                DatePicker("", selection: $customEndDate, displayedComponents: .date)
                                    .datePickerStyle(.compact).labelsHidden()
                            }
                        }

                        // 本月概览卡片
                        monthlySummaryCard

                        if let budgetReminder {
                            ledgerBudgetCard(budgetReminder)
                        }

                        // 交易列表 / 日历
                        if showCalendar {
                            CalendarView()
                        } else {
                            transactionList
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("账本")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            showCalendar.toggle()
                        }
                    } label: {
                        Image(systemName: showCalendar ? "list.bullet" : "calendar")
                            .foregroundStyle(DesignSystem.textSecondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        // 筛选按钮
                        Button {
                            showFilterSheet = true
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "line.3.horizontal.decrease")
                                    .font(.subheadline)
                                    .foregroundStyle(hasActiveFilters ? DesignSystem.primaryColor : DesignSystem.textSecondary)
                                if hasActiveFilters {
                                    Text("\(activeFilterCount)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 16, height: 16)
                                        .background(DesignSystem.primaryColor)
                                        .clipShape(Circle())
                                }
                            }
                        }

                        Button {
                            showReminders = true
                        } label: {
                            Image(systemName: "bell.badge.fill")
                                .foregroundStyle(DesignSystem.textSecondary)
                        }
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .foregroundStyle(DesignSystem.textSecondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddTransaction) {
                QuickEntryView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showReminders) {
                ReminderView {
                    showReminders = false
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                FilterSheetView(
                    typeFilter: $typeFilter,
                    categoryFilterId: $categoryFilterId,
                    minAmountText: $minAmountText,
                    maxAmountText: $maxAmountText
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $editingTransaction) { transaction in
                EditTransactionView(transaction: transaction)
            }
        }
    }

    // MARK: - Components

    private var monthlySummaryCard: some View {
        VStack(spacing: 16) {
            // 月份标题
            HStack {
                Text(Date().monthYearString)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.textSecondary)
                Spacer()
            }

            HStack(spacing: 0) {
                // 支出
                VStack(alignment: .leading, spacing: 4) {
                    Text("支出")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textSecondary)
                    Text(monthlyExpense.formattedCurrency)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(DesignSystem.expenseColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 收入
                VStack(alignment: .leading, spacing: 4) {
                    Text("收入")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textSecondary)
                    Text(hasHiddenMonthlyIncome ? privacyLock.maskedText : monthlyIncome.formattedCurrency)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(DesignSystem.incomeColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 结余
                VStack(alignment: .trailing, spacing: 4) {
                    Text("结余")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textSecondary)
                    Text(hasHiddenMonthlyIncome ? privacyLock.maskedText : (monthlyIncome - monthlyExpense).formattedCurrency)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(
                            monthlyIncome >= monthlyExpense
                            ? DesignSystem.incomeColor
                            : DesignSystem.expenseColor
                        )
                }
            }

            if hasHiddenMonthlyIncome {
                Button {
                    Task { _ = await privacyLock.unlock() }
                } label: {
                    Label("解锁查看工资收入", systemImage: "lock.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DesignSystem.primaryColor)
                }
            }
        }
        .glassCard()
    }

    private func ledgerBudgetCard(_ reminder: BudgetReminder) -> some View {
        let analysis = reminder.analysis

        return HStack(spacing: 12) {
            Image(systemName: reminder.iconName)
                .font(.headline)
                .foregroundStyle(budgetAccent(for: reminder.alertLevel))
                .frame(width: 34, height: 34)
                .background(budgetAccent(for: reminder.alertLevel).opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(reminder.shortMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.textPrimary)
                Text("剩余 \(analysis.daysRemaining) 天 · 预计月底 \(analysis.projectedTotal.formattedCurrency)")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textSecondary)
            }
            Spacer()
        }
        .padding()
        .background(DesignSystem.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .stroke(budgetAccent(for: reminder.alertLevel).opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 10, y: 5)
    }

    private func budgetAccent(for level: BudgetAlertLevel) -> Color {
        switch level {
        case .healthy: return DesignSystem.incomeColor
        case .warning: return DesignSystem.warningColor
        case .danger: return DesignSystem.dangerColor
        }
    }

    private var transactionList: some View {
        LazyVStack(spacing: 4) {
            if groupedTransactions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: hasActiveFilters || !searchText.isEmpty ? "line.3.horizontal.decrease.circle" : "tray")
                        .font(.system(size: 40))
                        .foregroundStyle(DesignSystem.textTertiary)
                    if hasActiveFilters || !searchText.isEmpty {
                        Text("没有匹配的交易记录")
                            .font(.subheadline)
                            .foregroundStyle(DesignSystem.textTertiary)
                        Text("试试调整筛选条件或搜索关键词")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.textTertiary)
                        if hasActiveFilters {
                            Button("清除筛选") {
                                withAnimation {
                                    typeFilter = .all
                                    categoryFilterId = nil
                                    minAmountText = ""
                                    maxAmountText = ""
                                    searchText = ""
                                }
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DesignSystem.primaryColor)
                        }
                    } else {
                        Text("暂无交易记录")
                            .font(.subheadline)
                            .foregroundStyle(DesignSystem.textTertiary)
                        Button("记一笔") {
                            showAddTransaction = true
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DesignSystem.primaryColor)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            }

            ForEach(groupedTransactions, id: \.0) { dateString, transactions in
                Section {
                    ForEach(transactions, id: \.id) { transaction in
                        TransactionRow(transaction: transaction, revealsPrivateIncome: privacyLock.isUnlocked)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isPrivateIncomeHidden(transaction) {
                                    Task { _ = await privacyLock.unlock() }
                                } else {
                                    editingTransaction = transaction
                                }
                            }
                            .contextMenu {
                                Button {
                                    if isPrivateIncomeHidden(transaction) {
                                        Task { _ = await privacyLock.unlock() }
                                    } else {
                                        editingTransaction = transaction
                                    }
                                } label: {
                                    Label(isPrivateIncomeHidden(transaction) ? "解锁查看" : "编辑", systemImage: isPrivateIncomeHidden(transaction) ? "lock.open" : "pencil")
                                }
                                Button(role: .destructive) {
                                    withAnimation {
                                        deleteTransaction(transaction)
                                    }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    withAnimation {
                                        deleteTransaction(transaction)
                                    }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    if isPrivateIncomeHidden(transaction) {
                                        Task { _ = await privacyLock.unlock() }
                                    } else {
                                        editingTransaction = transaction
                                    }
                                } label: {
                                    Label(isPrivateIncomeHidden(transaction) ? "解锁" : "编辑", systemImage: isPrivateIncomeHidden(transaction) ? "lock.open" : "pencil")
                                }
                                .tint(DesignSystem.primaryColor)
                            }
                    }
                } header: {
                    HStack {
                        Text(dateString)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DesignSystem.textTertiary)
                        Spacer()
                        let dayTotal = transactions.reduce(Decimal(0)) { $0 + $1.signedAmount }
                        let hasHiddenIncome = transactions.contains { isPrivateIncomeHidden($0) }
                        Text(hasHiddenIncome ? privacyLock.maskedText : dayTotal.formattedCurrency)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(DesignSystem.textTertiary)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 4)
                }
            }
        }
    }

    private func deleteTransaction(_ transaction: Transaction) {
        CashPoolService(modelContext: modelContext).reverse(delta: transaction.cashPoolDelta)
        modelContext.delete(transaction)
        try? modelContext.save()
    }
}

/// 单笔交易行
struct TransactionRow: View {
    let transaction: Transaction
    var revealsPrivateIncome = true

    private var hidesPrivateIncome: Bool {
        transaction.isProtectedIncome && !revealsPrivateIncome
    }

    var body: some View {
        HStack(spacing: 12) {
            // 分类图标
            ZStack {
                Circle()
                    .fill(rowColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: hidesPrivateIncome ? "lock.fill" : transaction.category?.icon ?? "questionmark")
                    .font(.subheadline)
                    .foregroundStyle(rowColor)
            }

            // 分类名和备注
            VStack(alignment: .leading, spacing: 2) {
                Text(hidesPrivateIncome ? "隐私收入" : transaction.category?.entryDisplayName ?? "未分类")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.textPrimary)
                if !hidesPrivateIncome && !transaction.note.isEmpty {
                    Text(transaction.note)
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 金额
            Text(hidesPrivateIncome ? "****" : "\(transaction.isExpense ? "-" : "+")\(transaction.amount.formattedAmount)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(
                    transaction.isExpense
                    ? DesignSystem.expenseColor
                    : DesignSystem.incomeColor
                )
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    private var rowColor: Color {
        hidesPrivateIncome ? DesignSystem.textTertiary : Color(hex: transaction.category?.colorHex ?? "#667EEA")
    }
}

// MARK: - 筛选条件标签

struct FilterChip: View {
    let label: String
    let color: Color
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
            Button {
                withAnimation(.spring(response: 0.3)) { onRemove() }
                HapticManager.selection()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
        .transition(.scale.combined(with: .opacity))
    }
}
