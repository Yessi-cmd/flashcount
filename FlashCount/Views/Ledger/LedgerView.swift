import SwiftUI
import SwiftData

/// 账本主页面 - 展示当前账本的交易列表和统计
struct LedgerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var privacyLock: PrivacyLockService
    @AppStorage("payday") private var payday = 1
    @AppStorage(WeekendBudgetPreferences.storageKey) private var weekendBudgetMultiplierPercent = WeekendBudgetPreferences.defaultRawValue
    @Query private var allTransactions: [Transaction]
    @Query(sort: \Budget.createdAt) private var allBudgets: [Budget]

    @Query(
        filter: #Predicate<Category> { !$0.isArchived },
        sort: \Category.sortOrder
    ) private var allCategories: [Category]

    @State private var showAddTransaction = false
    @State private var editingTransaction: Transaction?
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var dateFilter: LedgerPeriodFilter = .payCycle
    @State private var showCustomDatePicker = false
    @State private var showCalendar = false
    @State private var showSettings = false
    @State private var showReminders = false
    @State private var deleteError: String?
    @State private var undoInfo: DeletedTransactionSnapshot?
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
    @State private var sortField: TransactionSortField = .date
    @State private var sortDirection: TransactionSortDirection = .descending
    @State private var visibleTransactionLimit = 200
    @State private var historicalTransactions: [Transaction] = []

    private let transactionPageSize = 200
    private let recentCutoff: Date

    init() {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -120, to: calendar.startOfDay(for: Date())) ?? .distantPast
        recentCutoff = cutoff
        _allTransactions = Query(
            filter: #Predicate<Transaction> { $0.date >= cutoff },
            sort: \Transaction.date,
            order: .reverse
        )
    }

    private var presentationTransactions: [Transaction] {
        historicalTransactions + allTransactions
    }

    /// 单次渲染所需的交易数据。筛选、月度统计、按日分组在同一遍历中完成。
    private struct LedgerPresentation {
        struct MonthlySummary {
            let expense: Decimal
            let income: Decimal
            let hasHiddenIncome: Bool
        }

        struct DayGroup: Identifiable {
            let id: String
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
        let range = dateFilter.dateRange(
            referenceDate: now,
            payday: payday,
            customStart: customStartDate,
            customEnd: customEndDate,
            calendar: calendar
        )
        let selectedCategory = categoryFilterId.flatMap { id in allCategories.first { $0.id == id } }
        let categoryRootName = selectedCategory?.rootCategoryName == selectedCategory?.name ? selectedCategory?.name : nil
        let categoryID = categoryRootName == nil ? selectedCategory?.id : nil
        let selectedExpenseType: Bool? = typeFilter == .all ? nil : typeFilter == .expense
        let minAmount = Decimal(string: minAmountText).flatMap { $0 > 0 ? $0 : nil }
        let maxAmount = Decimal(string: maxAmountText).flatMap { $0 > 0 ? $0 : nil }
        let searchQuery = debouncedSearchText.isEmpty ? nil : debouncedSearchText.lowercased()

        var filteredTransactions: [Transaction] = []
        var expense: Decimal = 0
        var income: Decimal = 0
        var hasHiddenIncome = false
        var visibleTransactionsByDay: [Date: [Transaction]] = [:]
        var netTotalsByDay: [Date: Decimal] = [:]
        var hiddenIncomeByDay: Set<Date> = []

        for transaction in presentationTransactions {
            guard range?.contains(transaction.date) ?? true,
                  selectedExpenseType.map({ transaction.isExpense == $0 }) ?? true,
                  categoryRootName.map({ transaction.category?.rootCategoryName == $0 }) ?? true,
                  categoryID.map({ transaction.category?.id == $0 }) ?? true,
                  minAmount.map({ transaction.amount >= $0 }) ?? true,
                  maxAmount.map({ transaction.amount <= $0 }) ?? true
            else { continue }

            if let searchQuery {
                guard !isProtectedIncomeMetadataHidden(transaction),
                      transaction.note.lowercased().contains(searchQuery)
                        || transaction.category?.name.lowercased().contains(searchQuery) == true
                        || transaction.category?.rootCategoryName.lowercased().contains(searchQuery) == true
                        || "\(transaction.amount)".contains(searchQuery)
                else { continue }
            }

            filteredTransactions.append(transaction)
            let day = calendar.startOfDay(for: transaction.date)
            netTotalsByDay[day, default: 0] += transaction.signedAmount
            if isIncomeHidden(transaction) {
                hiddenIncomeByDay.insert(day)
            }

            if transaction.isExpense {
                expense += transaction.amount
            } else {
                income += transaction.amount
                if isIncomeHidden(transaction) { hasHiddenIncome = true }
            }
        }

        filteredTransactions.sort { lhs, rhs in
            switch sortField {
            case .date:
                if lhs.date != rhs.date {
                    return sortDirection == .ascending ? lhs.date < rhs.date : lhs.date > rhs.date
                }
                if lhs.createdAt != rhs.createdAt {
                    return sortDirection == .ascending ? lhs.createdAt < rhs.createdAt : lhs.createdAt > rhs.createdAt
                }
            case .amount:
                if lhs.amount != rhs.amount {
                    return sortDirection == .ascending ? lhs.amount < rhs.amount : lhs.amount > rhs.amount
                }
                if lhs.date != rhs.date {
                    return sortDirection == .ascending ? lhs.date < rhs.date : lhs.date > rhs.date
                }
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        let visibleTransactions = Array(filteredTransactions.prefix(visibleTransactionLimit))
        let dayGroups: [LedgerPresentation.DayGroup]
        if sortField == .date {
            for transaction in visibleTransactions {
                let day = calendar.startOfDay(for: transaction.date)
                visibleTransactionsByDay[day, default: []].append(transaction)
            }
            let orderedDays = visibleTransactionsByDay.keys.sorted {
                sortDirection == .ascending ? $0 < $1 : $0 > $1
            }
            dayGroups = orderedDays.map { day in
                LedgerPresentation.DayGroup(
                    id: "day-\(day.timeIntervalSinceReferenceDate)",
                    title: day.relativeString,
                    transactions: visibleTransactionsByDay[day] ?? [],
                    netTotal: netTotalsByDay[day] ?? 0,
                    hasHiddenIncome: hiddenIncomeByDay.contains(day)
                )
            }
        } else if visibleTransactions.isEmpty {
            dayGroups = []
        } else {
            dayGroups = [LedgerPresentation.DayGroup(
                id: "amount",
                title: sortDirection.detail(for: .amount),
                transactions: visibleTransactions,
                netTotal: filteredTransactions.reduce(0) { $0 + $1.signedAmount },
                hasHiddenIncome: filteredTransactions.contains(where: isIncomeHidden)
            )]
        }

        return LedgerPresentation(
            filteredTransactions: filteredTransactions,
            visibleTransactionCount: visibleTransactions.count,
            monthlySummary: .init(expense: expense, income: income, hasHiddenIncome: hasHiddenIncome),
            dayGroups: dayGroups
        )
    }

    private var budgetReminder: BudgetReminder? {
        BudgetReminderService.reminder(
            budgets: allBudgets,
            transactions: allTransactions,
            ledger: nil,
            payday: payday,
            weekendMultiplier: WeekendBudgetPreferences.multiplier(for: weekendBudgetMultiplierPercent)
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

    private var hasCustomSort: Bool {
        sortField != .date || sortDirection != .descending
    }

    private func isIncomeHidden(_ transaction: Transaction) -> Bool {
        PrivacyVisibilityPolicy.hidesIncome(
            isExpense: transaction.isExpense,
            isUnlocked: privacyLock.isUnlocked
        )
    }

    private func isProtectedIncomeMetadataHidden(_ transaction: Transaction) -> Bool {
        PrivacyVisibilityPolicy.hidesProtectedMetadata(
            isProtectedIncome: transaction.isProtectedIncome,
            isUnlocked: privacyLock.isUnlocked
        )
    }

    var body: some View {
        let presentation = makePresentation(visibleTransactionLimit: visibleTransactionLimit)

        return NavigationStack {
            ZStack {
                AmbientBackground(accent: DesignSystem.primaryColor)

                ScrollView {
                    VStack(spacing: DesignSystem.sectionSpacing) {
                        // B 方向先呈现核心结论，再提供搜索与筛选工具。
                        monthlySummaryCard(presentation.monthlySummary)

                        if let budgetReminder {
                            ledgerBudgetCard(budgetReminder)
                        }

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
                        dateFilterStrip

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
                            .accessibilityLabel("批量选择")
                            .accessibilityIdentifier("ledger.batchSelect")

                            // 筛选按钮
                            Button {
                                showFilterSheet = true
                            } label: {
                                HStack(spacing: 2) {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.subheadline)
                                        .foregroundStyle(hasActiveFilters || hasCustomSort ? DesignSystem.primaryColor : DesignSystem.textSecondary)
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
                            .accessibilityLabel("筛选与排序，当前\(sortDirection.detail(for: sortField))")

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
                            .accessibilityLabel("设置")
                            .accessibilityIdentifier("ledger.settings")
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
                    maxAmountText: $maxAmountText,
                    sortField: $sortField,
                    sortDirection: $sortDirection
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelecting {
                    batchActionBar(transactions: presentation.filteredTransactions)
                } else {
                    undoDeleteToast
                }
            }
            .task(id: searchText) {
                // 防抖：用户停止输入 300ms 后再执行搜索过滤
                do {
                    try await Task.sleep(for: .milliseconds(300))
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                debouncedSearchText = searchText
            }
            .task(id: historyQueryID) {
                loadHistoricalTransactionsIfNeeded()
            }
            .onChange(of: debouncedSearchText) { resetVisibleTransactionLimit() }
            .onChange(of: dateFilter) { resetVisibleTransactionLimit() }
            .onChange(of: typeFilter) { resetVisibleTransactionLimit() }
            .onChange(of: categoryFilterId) { resetVisibleTransactionLimit() }
            .onChange(of: minAmountText) { resetVisibleTransactionLimit() }
            .onChange(of: maxAmountText) { resetVisibleTransactionLimit() }
            .onChange(of: customStartDate) { resetVisibleTransactionLimit() }
            .onChange(of: customEndDate) { resetVisibleTransactionLimit() }
            .onChange(of: sortField) { resetVisibleTransactionLimit() }
            .onChange(of: sortDirection) { resetVisibleTransactionLimit() }
        }
    }

    private func resetVisibleTransactionLimit() {
        visibleTransactionLimit = transactionPageSize
    }

    private var historyQueryID: String {
        "\(dateFilter.rawValue)-\(customStartDate.timeIntervalSinceReferenceDate)-\(customEndDate.timeIntervalSinceReferenceDate)"
    }

    private func loadHistoricalTransactionsIfNeeded() {
        let requiresHistory = dateFilter == .all
            || (dateFilter == .custom && min(customStartDate, customEndDate) < recentCutoff)
        guard requiresHistory else {
            historicalTransactions = []
            return
        }

        let upperBound = recentCutoff
        let descriptor: FetchDescriptor<Transaction>
        if dateFilter == .custom {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: min(customStartDate, customEndDate))
            descriptor = FetchDescriptor(
                predicate: #Predicate<Transaction> { $0.date >= start && $0.date < upperBound },
                sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate<Transaction> { $0.date < upperBound },
                sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
            )
        }
        do {
            historicalTransactions = try modelContext.fetch(descriptor)
        } catch {
            historicalTransactions = []
            deleteError = error.localizedDescription
        }
    }

    // MARK: - Components

    @ViewBuilder
    private var dateFilterStrip: some View {
        if #available(iOS 26.0, *) {
            liquidGlassDateFilterStrip
        } else {
            legacyDateFilterStrip
        }
    }

    @available(iOS 26.0, *)
    private var liquidGlassDateFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LiquidGlassContainer(spacing: 6) {
                HStack(spacing: 8) {
                    ForEach(LedgerPeriodFilter.allCases, id: \.self) { filter in
                        let isSelected = dateFilter == filter
                        Button {
                            selectDateFilter(filter)
                        } label: {
                            Text(filter.rawValue)
                                .font(.caption.weight(isSelected ? .semibold : .medium))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 7)
                                .foregroundStyle(isSelected ? DesignSystem.primaryColor : DesignSystem.textSecondary)
                                .contentShape(Capsule())
                                .liquidGlassSurface(
                                    tint: isSelected ? DesignSystem.primaryColor.opacity(0.18) : nil,
                                    shape: .capsule,
                                    isInteractive: true,
                                    isClear: !isSelected
                                )
                                .animation(reduceMotion ? nil : DesignSystem.glassSelectionAnimation, value: isSelected)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var legacyDateFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LedgerPeriodFilter.allCases, id: \.self) { filter in
                    Button {
                        selectDateFilter(filter)
                    } label: {
                        Text(filter.rawValue)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                dateFilter == filter
                                    ? DesignSystem.primaryColor.opacity(0.16)
                                    : DesignSystem.softFill
                            )
                            .foregroundStyle(dateFilter == filter ? DesignSystem.primaryColor : DesignSystem.textSecondary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func selectDateFilter(_ filter: LedgerPeriodFilter) {
        withAnimation(reduceMotion ? nil : DesignSystem.glassSelectionAnimation) {
            dateFilter = filter
        }
        HapticManager.selection()
    }

    private func monthlySummaryCard(_ summary: LedgerPresentation.MonthlySummary) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text(summaryPeriodDescription)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.textSecondary)
                Spacer()
                PrivacyVisibilityButton()
                    .font(.subheadline)
                    .frame(width: 32, height: 32)
                    .background(DesignSystem.softFill)
                    .clipShape(Circle())
                    .buttonStyle(PressableButtonStyle())
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("\(dateFilter.metricPrefix)支出")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.textSecondary)
                Text(summary.expense.formattedCurrency)
                    .font(.system(size: 38, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(DesignSystem.textPrimary)
            }

            HStack(spacing: 9) {
                summarySecondaryMetric(
                    title: "\(dateFilter.metricPrefix)收入",
                    value: summary.hasHiddenIncome ? privacyLock.maskedText : summary.income.formattedCurrency,
                    color: DesignSystem.textPrimary
                )
                summarySecondaryMetric(
                    title: "\(dateFilter.metricPrefix)结余",
                    value: summary.hasHiddenIncome ? privacyLock.maskedText : (summary.income - summary.expense).formattedCurrency,
                    color: summary.hasHiddenIncome ? DesignSystem.textTertiary : (summary.income >= summary.expense ? DesignSystem.textPrimary : DesignSystem.expenseColor)
                )
            }

            if summary.hasHiddenIncome {
                Button {
                    privacyLock.requestReveal()
                } label: {
                    Label("验证并显示全部收入", systemImage: "lock.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DesignSystem.primaryColor)
                }
            }
        }
        .heroCard(accent: DesignSystem.primaryColor)
    }

    private var summaryPeriodDescription: String {
        let calendar = Calendar.current
        let now = Date()
        switch dateFilter {
        case .today:
            return now.fullDateString
        case .thisWeek, .thisMonth, .payCycle, .custom:
            guard let range = dateFilter.dateRange(
                referenceDate: now,
                payday: payday,
                customStart: customStartDate,
                customEnd: customEndDate,
                calendar: calendar
            ) else { return dateFilter.rawValue }
            let finalDay = calendar.date(byAdding: .day, value: -1, to: range.upperBound) ?? range.upperBound
            return "\(range.lowerBound.shortDateString) – \(finalDay.shortDateString)"
        case .all:
            return "全部记录"
        }
    }

    private func summarySecondaryMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(DesignSystem.textTertiary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(DesignSystem.softFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius, style: .continuous))
    }

    private func ledgerBudgetCard(_ reminder: BudgetReminder) -> some View {
        let analysis = reminder.analysis
        let alertAccent = budgetAccent(for: reminder.alertLevel)
        let borderAccent = reminder.isWeekendAllowanceAdjusted ? DesignSystem.weekendColor : alertAccent

        return HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: reminder.iconName)
                    .font(.headline)
                    .foregroundStyle(alertAccent)
                if reminder.isWeekendAllowanceAdjusted {
                    Image(systemName: "calendar")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DesignSystem.cardBackground)
                        .padding(3)
                        .background(DesignSystem.weekendColor)
                        .clipShape(Circle())
                        .accessibilityLabel("周末额度")
                }
            }
            .frame(width: 34, height: 34)
            .background(alertAccent.opacity(0.12))
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
                .stroke(borderAccent.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 10, y: 4)
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
                        hidesIncome: privacyLock.hidesSensitiveAmounts
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
                            } else if isIncomeHidden(transaction) {
                                privacyLock.requestReveal()
                            } else {
                                editingTransaction = transaction
                            }
                        }
                        .accessibilityAddTraits(.isButton)
                        .contextMenu {
                            if !isSelecting {
                                Button {
                                    if isIncomeHidden(transaction) {
                                        privacyLock.requestReveal()
                                    } else {
                                        editingTransaction = transaction
                                    }
                                } label: {
                                    Label(isIncomeHidden(transaction) ? "验证后查看" : "编辑", systemImage: isIncomeHidden(transaction) ? "lock.open" : "pencil")
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
                                    if isIncomeHidden(transaction) {
                                        privacyLock.requestReveal()
                                    } else {
                                        editingTransaction = transaction
                                    }
                                } label: {
                                    Label(isIncomeHidden(transaction) ? "验证" : "编辑", systemImage: isIncomeHidden(transaction) ? "lock.open" : "pencil")
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
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DesignSystem.borderColor, lineWidth: 1))
                .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
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
            .accessibilityIdentifier("ledger.batchDone")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DesignSystem.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DesignSystem.borderColor, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func batchDeleteSelected(from transactions: [Transaction]) {
        let toDelete = transactions.filter { selectedIds.contains($0.id) }
        do {
            try TransactionMutationService(modelContext: modelContext).delete(toDelete)
            HapticManager.success()
            withAnimation(.spring(response: 0.3)) {
                selectedIds.removeAll()
                isSelecting = false
            }
        } catch {
            batchDeleteError = error.localizedDescription
        }
    }

    private func deleteTransaction(_ transaction: Transaction) {
        let snapshot: DeletedTransactionSnapshot
        do {
            snapshot = try TransactionMutationService(modelContext: modelContext).delete(transaction)
        } catch {
            deleteError = error.localizedDescription
            return
        }

        // 显示撤销条
        withAnimation(.spring(response: 0.3)) {
            undoInfo = snapshot
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

        do {
            try TransactionMutationService(modelContext: modelContext).restore(info)
        } catch {
            deleteError = error.localizedDescription
            HapticManager.error()
            return
        }

        withAnimation(.spring(response: 0.3)) {
            undoInfo = nil
        }
        HapticManager.success()
    }
}
