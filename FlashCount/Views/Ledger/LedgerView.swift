import SwiftUI
import SwiftData

/// 账本主页面 - 展示当前账本的交易列表和统计
struct LedgerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var privacyLock: PrivacyLockService
    @AppStorage("payday") private var payday = 1
    @AppStorage("hideHomeIncome") private var hideHomeIncome = true
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \Budget.createdAt) private var allBudgets: [Budget]

    @Query(
        filter: #Predicate<Category> { !$0.isArchived },
        sort: \Category.sortOrder
    ) private var allCategories: [Category]

    @State private var showAddTransaction = false
    @State private var editingTransaction: Transaction?
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var dateFilter: DateFilter = .all
    @State private var showCustomDatePicker = false
    @State private var showCalendar = false
    @State private var showSettings = false
    @State private var showReminders = false
    @State private var deleteError: String?
    @State private var undoInfo: UndoDeleteInfo?
    @State private var undoWorkItem: DispatchWorkItem?
    @State private var isSelecting = false
    @State private var selectedIds = Set<UUID>()
    @State private var batchDeleteError: String?
    @State private var customStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    @State private var customEndDate = Date()

    // 高级筛选状态
    @State private var showFilterSheet = false
    @State private var typeFilter: TransactionTypeFilter = .all
    @State private var categoryFilterId: UUID?
    @State private var minAmountText = ""
    @State private var maxAmountText = ""
    @State private var visibleTransactionLimit = 200

    private let transactionPageSize = 200

    enum DateFilter: String, CaseIterable {
        case all = "全部"
        case today = "今天"
        case thisWeek = "本周"
        case thisMonth = "本月"
        case custom = "自定义"
    }

    /// 单次渲染所需的交易数据。筛选、月度统计、按日分组在同一遍历中完成。
    private struct LedgerPresentation {
        struct MonthlySummary {
            let expense: Decimal
            let income: Decimal
            let hasHiddenIncome: Bool
        }

        struct DayGroup: Identifiable {
            let id: Date
            let title: String
            let transactions: [Transaction]
            let netTotal: Decimal
            let hasHiddenIncome: Bool
        }

        let filteredTransactions: [Transaction]
        let visibleTransactionCount: Int
        let monthlySummary: MonthlySummary
        let dayGroups: [DayGroup]

        var hasMoreTransactions: Bool {
            visibleTransactionCount < filteredTransactions.count
        }
    }

    private func makePresentation(visibleTransactionLimit: Int) -> LedgerPresentation {
        let calendar = Calendar.current
        let now = Date()
        let range: Range<Date>?
        switch dateFilter {
        case .all:
            range = nil
        case .today:
            range = calendar.startOfDay(for: now)..<Date.distantFuture
        case .thisWeek:
            range = (calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now)..<Date.distantFuture
        case .thisMonth:
            range = (calendar.dateInterval(of: .month, for: now)?.start ?? now)..<Date.distantFuture
        case .custom:
            let start = calendar.startOfDay(for: customStartDate)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEndDate)) ?? start
            range = start..<end
        }
        let selectedCategory = categoryFilterId.flatMap { id in allCategories.first { $0.id == id } }
        let categoryRootName = selectedCategory?.rootCategoryName == selectedCategory?.name ? selectedCategory?.name : nil
        let categoryID = categoryRootName == nil ? selectedCategory?.id : nil
        let selectedExpenseType: Bool? = typeFilter == .all ? nil : typeFilter == .expense
        let minAmount = Decimal(string: minAmountText).flatMap { $0 > 0 ? $0 : nil }
        let maxAmount = Decimal(string: maxAmountText).flatMap { $0 > 0 ? $0 : nil }
        let searchQuery = debouncedSearchText.isEmpty ? nil : debouncedSearchText.lowercased()
        let currentMonth = calendar.dateInterval(of: .month, for: now)

        var filteredTransactions: [Transaction] = []
        var expense: Decimal = 0
        var income: Decimal = 0
        var hasHiddenIncome = hideHomeIncome
        var visibleTransactionsByDay: [Date: [Transaction]] = [:]
        var netTotalsByDay: [Date: Decimal] = [:]
        var hiddenIncomeByDay: Set<Date> = []

        for transaction in allTransactions {
            guard range?.contains(transaction.date) ?? true,
                  selectedExpenseType.map({ transaction.isExpense == $0 }) ?? true,
                  categoryRootName.map({ transaction.category?.rootCategoryName == $0 }) ?? true,
                  categoryID.map({ transaction.category?.id == $0 }) ?? true,
                  minAmount.map({ transaction.amount >= $0 }) ?? true,
                  maxAmount.map({ transaction.amount <= $0 }) ?? true
            else { continue }

            if let searchQuery {
                guard !isPrivateIncomeHidden(transaction),
                      transaction.note.lowercased().contains(searchQuery)
                        || transaction.category?.name.lowercased().contains(searchQuery) == true
                        || transaction.category?.rootCategoryName.lowercased().contains(searchQuery) == true
                        || "\(transaction.amount)".contains(searchQuery)
                else { continue }
            }

            filteredTransactions.append(transaction)
            let day = calendar.startOfDay(for: transaction.date)
            netTotalsByDay[day, default: 0] += transaction.signedAmount
            if isPrivateIncomeHidden(transaction) || (hideHomeIncome && !transaction.isExpense) {
                hiddenIncomeByDay.insert(day)
            }

            if filteredTransactions.count <= visibleTransactionLimit {
                visibleTransactionsByDay[day, default: []].append(transaction)
            }

            if currentMonth?.contains(transaction.date) == true {
                if transaction.isExpense {
                    expense += transaction.amount
                } else if isPrivateIncomeHidden(transaction) {
                    hasHiddenIncome = true
                } else {
                    income += transaction.amount
                    if hideHomeIncome { hasHiddenIncome = true }
                }
            }
        }

        let dayGroups = visibleTransactionsByDay.keys.sorted(by: >).map { day in
            LedgerPresentation.DayGroup(
                id: day,
                title: day.relativeString,
                transactions: visibleTransactionsByDay[day] ?? [],
                netTotal: netTotalsByDay[day] ?? 0,
                hasHiddenIncome: hiddenIncomeByDay.contains(day)
            )
        }

        return LedgerPresentation(
            filteredTransactions: filteredTransactions,
            visibleTransactionCount: min(filteredTransactions.count, visibleTransactionLimit),
            monthlySummary: .init(expense: expense, income: income, hasHiddenIncome: hasHiddenIncome),
            dayGroups: dayGroups
        )
    }

    private var budgetReminder: BudgetReminder? {
        BudgetReminderService.reminder(
            budgets: allBudgets,
            transactions: allTransactions,
            ledger: nil,
            payday: payday
        )
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
        let presentation = makePresentation(visibleTransactionLimit: visibleTransactionLimit)

        return NavigationStack {
            ZStack {
                AmbientBackground(accent: DesignSystem.primaryColor)

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
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    showCustomDatePicker.toggle()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: showCustomDatePicker ? "chevron.up" : "chevron.down")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(DesignSystem.primaryColor)
                                    Text("\(customStartDate.shortDateString) → \(customEndDate.shortDateString)")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(DesignSystem.textPrimary)
                                    Spacer()
                                    Image(systemName: "calendar")
                                        .font(.caption)
                                        .foregroundStyle(DesignSystem.textTertiary)
                                }
                                .padding(10)
                                .background(DesignSystem.softFill)
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                            }
                            .buttonStyle(.plain)

                            if showCustomDatePicker {
                                HStack(spacing: 12) {
                                    DatePicker("开始", selection: $customStartDate, displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                    Text("→")
                                        .foregroundStyle(DesignSystem.textTertiary)
                                    DatePicker("结束", selection: $customEndDate, displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                }
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }

                        // 本月概览卡片
                        monthlySummaryCard(presentation.monthlySummary)

                        if let budgetReminder {
                            ledgerBudgetCard(budgetReminder)
                        }

                        // 交易列表 / 日历
                        if showCalendar {
                            CalendarView()
                        } else {
                            transactionList(presentation)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("账本")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if isSelecting {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") {
                            withAnimation(.spring(response: 0.3)) {
                                isSelecting = false
                                selectedIds.removeAll()
                            }
                        }
                        .foregroundStyle(DesignSystem.primaryColor)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            Text("已选 \(selectedIds.count)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(DesignSystem.textSecondary)

                            Button(selectedIds.count == presentation.filteredTransactions.count ? "取消全选" : "全选") {
                                withAnimation(.spring(response: 0.3)) {
                                    if selectedIds.count == presentation.filteredTransactions.count {
                                        selectedIds.removeAll()
                                    } else {
                                        selectedIds = Set(presentation.filteredTransactions.map(\.id))
                                    }
                                }
                            }
                            .foregroundStyle(DesignSystem.primaryColor)
                        }
                    }
                } else {
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
                            // 批量选择
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    isSelecting = true
                                }
                            } label: {
                                Image(systemName: "checkmark.circle")
                                    .font(.subheadline)
                                    .foregroundStyle(DesignSystem.textSecondary)
                            }

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
            .saveErrorAlert($deleteError)
            .alert("批量删除失败", isPresented: .init(
                get: { batchDeleteError != nil },
                set: { if !$0 { batchDeleteError = nil } }
            )) {
                Button("好的", role: .cancel) { batchDeleteError = nil }
            } message: {
                Text(batchDeleteError ?? "未知错误")
            }
            .overlay(alignment: .bottom) {
                if isSelecting {
                    batchActionBar(transactions: presentation.filteredTransactions)
                } else {
                    undoDeleteToast
                }
            }
            .task(id: searchText) {
                // 防抖：用户停止输入 300ms 后再执行搜索过滤
                try? await Task.sleep(nanoseconds: 300_000_000)
                debouncedSearchText = searchText
            }
            .onChange(of: debouncedSearchText) { resetVisibleTransactionLimit() }
            .onChange(of: dateFilter) { resetVisibleTransactionLimit() }
            .onChange(of: typeFilter) { resetVisibleTransactionLimit() }
            .onChange(of: categoryFilterId) { resetVisibleTransactionLimit() }
            .onChange(of: minAmountText) { resetVisibleTransactionLimit() }
            .onChange(of: maxAmountText) { resetVisibleTransactionLimit() }
            .onChange(of: customStartDate) { resetVisibleTransactionLimit() }
            .onChange(of: customEndDate) { resetVisibleTransactionLimit() }
        }
    }

    private func resetVisibleTransactionLimit() {
        visibleTransactionLimit = transactionPageSize
    }

    // MARK: - Components

    private func monthlySummaryCard(_ summary: LedgerPresentation.MonthlySummary) -> some View {
        VStack(spacing: 16) {
            // 月份标题
            HStack {
                Text(Date().monthYearString)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.textSecondary)
                Spacer()
                Button {
                    hideHomeIncome.toggle()
                    HapticManager.selection()
                } label: {
                    Image(systemName: hideHomeIncome ? "eye.slash.fill" : "eye.fill")
                        .font(.subheadline)
                        .foregroundStyle(hideHomeIncome ? DesignSystem.textTertiary : DesignSystem.primaryColor)
                        .frame(width: 32, height: 32)
                        .background(DesignSystem.softFill)
                        .clipShape(Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(hideHomeIncome ? "显示首页收入" : "隐藏首页收入")
            }

            HStack(spacing: 0) {
                // 支出
                VStack(alignment: .leading, spacing: 4) {
                    Text("支出")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textSecondary)
                    Text(summary.expense.formattedCurrency)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(DesignSystem.expenseColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 收入
                VStack(alignment: .leading, spacing: 4) {
                    Text("收入")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textSecondary)
                    Text(summary.hasHiddenIncome ? privacyLock.maskedText : summary.income.formattedCurrency)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(DesignSystem.incomeColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 结余
                VStack(alignment: .trailing, spacing: 4) {
                    Text("结余")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textSecondary)
                    Text(summary.hasHiddenIncome ? privacyLock.maskedText : (summary.income - summary.expense).formattedCurrency)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(
                            summary.income >= summary.expense
                            ? DesignSystem.incomeColor
                            : DesignSystem.expenseColor
                        )
                }
            }

            if summary.hasHiddenIncome && !hideHomeIncome {
                Button {
                    Task { _ = await privacyLock.unlock() }
                } label: {
                    Label("解锁查看工资收入", systemImage: "lock.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DesignSystem.primaryColor)
                }
            }
        }
        .heroCard(accent: summary.income >= summary.expense ? DesignSystem.incomeColor : DesignSystem.expenseColor)
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

    private func transactionList(_ presentation: LedgerPresentation) -> some View {
        LazyVStack(spacing: 4) {
            if presentation.dayGroups.isEmpty {
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
                                    debouncedSearchText = ""
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

            ForEach(presentation.dayGroups) { group in
                Section {
                    ForEach(group.transactions, id: \.id) { transaction in
                let isSelected = selectedIds.contains(transaction.id)

                HStack(spacing: 0) {
                    if isSelecting {
                        Button {
                            withAnimation(.spring(response: 0.2)) {
                                if isSelected {
                                    selectedIds.remove(transaction.id)
                                } else {
                                    selectedIds.insert(transaction.id)
                                }
                            }
                        } label: {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isSelected ? DesignSystem.primaryColor : DesignSystem.textTertiary)
                                .frame(width: 36, height: 36)
                        }
                    }

                    TransactionRow(
                        transaction: transaction,
                        revealsPrivateIncome: privacyLock.isUnlocked,
                        hidesIncome: hideHomeIncome
                    )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSelecting {
                                withAnimation(.spring(response: 0.2)) {
                                    if isSelected {
                                        selectedIds.remove(transaction.id)
                                    } else {
                                        selectedIds.insert(transaction.id)
                                    }
                                }
                            } else if isPrivateIncomeHidden(transaction) {
                                Task { _ = await privacyLock.unlock() }
                            } else {
                                editingTransaction = transaction
                            }
                        }
                        .contextMenu {
                            if !isSelecting {
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
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if !isSelecting {
                                Button(role: .destructive) {
                                    withAnimation {
                                        deleteTransaction(transaction)
                                    }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if !isSelecting {
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
                        .opacity(isSelecting && isSelected ? 1 : (isSelecting ? 0.7 : 1))
                        .background(isSelecting && isSelected ? DesignSystem.primaryColor.opacity(0.06) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
                } header: {
                    HStack {
                        Text(group.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DesignSystem.textTertiary)
                        Spacer()
                        Text(group.hasHiddenIncome ? privacyLock.maskedText : group.netTotal.formattedCurrency)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(DesignSystem.textTertiary)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 4)
                }
            }

            if presentation.hasMoreTransactions {
                Button {
                    withAnimation(DesignSystem.standardAnimation) {
                        visibleTransactionLimit += transactionPageSize
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text("继续加载")
                            .font(.subheadline.weight(.semibold))
                        Text("已显示 \(presentation.visibleTransactionCount) / \(presentation.filteredTransactions.count) 笔")
                            .font(.caption2.monospacedDigit())
                    }
                    .foregroundStyle(DesignSystem.primaryColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.space12)
                    .background(DesignSystem.primaryColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.top, DesignSystem.space12)
            }
        }
    }

    // MARK: - 删除撤销 Toast

    private var undoDeleteToast: some View {
        Group {
            if undoInfo != nil {
                HStack(spacing: 12) {
                    Image(systemName: "trash")
                        .font(.subheadline)
                        .foregroundStyle(DesignSystem.textSecondary)

                    Text("已删除 1 笔")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DesignSystem.textPrimary)

                    Spacer(minLength: 8)

                    Button {
                        undoDelete()
                    } label: {
                        Text("撤销")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DesignSystem.primaryColor)
                    }

                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            undoInfo = nil
                        }
                        undoWorkItem?.cancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(DesignSystem.textTertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(DesignSystem.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - 批量操作栏

    private func batchActionBar(transactions: [Transaction]) -> some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                batchDeleteSelected(from: transactions)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("删除 (\(selectedIds.count))")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selectedIds.isEmpty ? DesignSystem.textTertiary : DesignSystem.dangerColor)
            }
            .disabled(selectedIds.isEmpty)

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3)) {
                    isSelecting = false
                    selectedIds.removeAll()
                }
            } label: {
                Text("完成")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func batchDeleteSelected(from transactions: [Transaction]) {
        let toDelete = transactions.filter { selectedIds.contains($0.id) }
        for transaction in toDelete {
            CashPoolService(modelContext: modelContext).reverse(delta: transaction.cashPoolDelta)
            modelContext.delete(transaction)
        }
        if let error = safeSave(modelContext) {
            modelContext.rollback()
            batchDeleteError = error
        } else {
            HapticManager.success()
            withAnimation(.spring(response: 0.3)) {
                selectedIds.removeAll()
                isSelecting = false
            }
        }
    }

    private func deleteTransaction(_ transaction: Transaction) {
        // 保存事务数据以便撤销
        let info = UndoDeleteInfo(
            amount: transaction.amount,
            isExpense: transaction.isExpense,
            note: transaction.note,
            date: transaction.date,
            isPrivateIncome: transaction.isPrivateIncome,
            cashPoolDelta: transaction.cashPoolDelta,
            category: transaction.category,
            ledger: transaction.ledger,
            recurringRule: transaction.recurringRule
        )
        CashPoolService(modelContext: modelContext).reverse(delta: transaction.cashPoolDelta)
        modelContext.delete(transaction)
        if let error = safeSave(modelContext) {
            modelContext.rollback()
            deleteError = error
            return
        }

        // 显示撤销条
        withAnimation(.spring(response: 0.3)) {
            undoInfo = info
        }
        undoWorkItem?.cancel()
        let task = DispatchWorkItem { [self] in
            withAnimation(.spring(response: 0.3)) {
                self.undoInfo = nil
            }
        }
        undoWorkItem = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: task)
    }

    private func undoDelete() {
        guard let info = undoInfo else { return }
        undoWorkItem?.cancel()

        let transaction = Transaction(
            amount: info.amount,
            isExpense: info.isExpense,
            note: info.note,
            date: info.date,
            isPrivateIncome: info.isPrivateIncome,
            cashPoolDelta: info.cashPoolDelta,
            category: info.category,
            ledger: info.ledger,
            recurringRule: info.recurringRule
        )
        modelContext.insert(transaction)
        if let delta = info.cashPoolDelta {
            CashPoolService(modelContext: modelContext).apply(delta: delta)
        }

        if let error = safeSave(modelContext) {
            deleteError = error
        }

        withAnimation(.spring(response: 0.3)) {
            undoInfo = nil
        }
        HapticManager.success()
    }
}

// MARK: - 撤销删除信息
private struct UndoDeleteInfo {
    let amount: Decimal
    let isExpense: Bool
    let note: String
    let date: Date
    let isPrivateIncome: Bool
    let cashPoolDelta: Decimal?
    let category: Category?
    let ledger: Ledger?
    let recurringRule: RecurringRule?
}

/// 单笔交易行
struct TransactionRow: View {
    let transaction: Transaction
    var revealsPrivateIncome = true
    var hidesIncome = false

    private var hidesPrivateIncome: Bool {
        transaction.isProtectedIncome && !revealsPrivateIncome
    }

    private var hidesIncomeAmount: Bool {
        hidesPrivateIncome || (hidesIncome && !transaction.isExpense)
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
            Text(hidesIncomeAmount ? "****" : "\(transaction.isExpense ? "-" : "+")\(transaction.amount.formattedCompactAmount)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(
                    transaction.isExpense
                    ? DesignSystem.expenseColor
                    : DesignSystem.incomeColor
                )
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
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
