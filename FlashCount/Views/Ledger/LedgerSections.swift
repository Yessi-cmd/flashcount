import SwiftUI
import SwiftData

// MARK: - 账本页各区块视图

extension LedgerView {
    /// 吸顶区：搜索、生效中的筛选标签、日期条、自定义区间。
    /// 需要不透明底色，否则吸顶时下方列表会从字缝里透出来。
    var stickyFilterHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(DesignSystem.textTertiary)
                TextField("搜索备注、分类、金额...", text: $filterState.searchText)
                    .font(.subheadline)
                    .foregroundStyle(DesignSystem.textPrimary)
                if !filterState.searchText.isEmpty {
                    Button {
                        filterState.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.textTertiary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("清除搜索")
                    .accessibilityIdentifier("ledger.clearSearch")
                }
            }
            .padding(10)
            .background(DesignSystem.softFill)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if filterState.hasActiveFilters {
                activeFilterChips
            }

            dateFilterStrip

            if filterState.dateFilter == .custom {
                customDateRangeControls
            }
        }
        .padding(.vertical, 8)
        .background {
            // 吸顶时要盖住滚过去的内容；两侧撑出页面 padding，避免露出一条缝。
            DesignSystem.surfaceBackground
                .padding(.horizontal, -DesignSystem.space16)
                .ignoresSafeArea(edges: .horizontal)
        }
        .accessibilityIdentifier("ledger.filterHeader")
    }

    private var activeFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if filterState.typeFilter != .all {
                    FilterChip(
                        label: filterState.typeFilter.rawValue,
                        color: filterState.typeFilter == .expense ? DesignSystem.expenseColor : DesignSystem.incomeColor
                    ) { filterState.typeFilter = .all }
                }
                if let id = filterState.categoryFilterId,
                   let cat = allCategories.first(where: { $0.id == id }) {
                    FilterChip(
                        label: cat.name,
                        color: Color(hex: cat.colorHex)
                    ) { filterState.categoryFilterId = nil }
                }
                if let minVal = Decimal(string: filterState.minAmountText), minVal > 0 {
                    FilterChip(
                        label: "¥\(minVal.formattedAmount)以上",
                        color: DesignSystem.primaryColor
                    ) { filterState.minAmountText = "" }
                }
                if let maxVal = Decimal(string: filterState.maxAmountText), maxVal > 0 {
                    FilterChip(
                        label: "¥\(maxVal.formattedAmount)以下",
                        color: DesignSystem.primaryColor
                    ) { filterState.maxAmountText = "" }
                }
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                        filterState.clearAdvancedFilters()
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

    @ViewBuilder
    private var customDateRangeControls: some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                showCustomDatePicker.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: showCustomDatePicker ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DesignSystem.primaryColor)
                Text("\(filterState.customStartDate.shortDateString) → \(filterState.customEndDate.shortDateString)")
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
                DatePicker("开始", selection: $filterState.customStartDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                Text("→")
                    .foregroundStyle(DesignSystem.textTertiary)
                DatePicker("结束", selection: $filterState.customEndDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// 列表主体：日历或交易列表。
    @ViewBuilder
    func ledgerBody(_ presentation: LedgerPresentation) -> some View {
        if showCalendar {
            CalendarView()
        } else {
            transactionList(presentation)
        }
    }

    @ViewBuilder
    var dateFilterStrip: some View {
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
                        let isSelected = filterState.dateFilter == filter
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
                                filterState.dateFilter == filter
                                    ? DesignSystem.primaryColor.opacity(0.16)
                                    : DesignSystem.softFill
                            )
                            .foregroundStyle(filterState.dateFilter == filter ? DesignSystem.primaryColor : DesignSystem.textSecondary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func selectDateFilter(_ filter: LedgerPeriodFilter) {
        withAnimation(reduceMotion ? nil : DesignSystem.glassSelectionAnimation) {
            filterState.dateFilter = filter
        }
        HapticManager.selection()
    }

    func monthlySummaryCard(_ summary: LedgerPresentation.MonthlySummary) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text(summaryPeriodDescription)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.textSecondary)
                Spacer()
                PrivacyVisibilityButton()
                    .font(.subheadline)
                    .frame(width: 44, height: 44)
                    .background(DesignSystem.softFill)
                    .clipShape(Circle())
                    .buttonStyle(PressableButtonStyle())
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("\(filterState.dateFilter.metricPrefix)支出")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.textSecondary)
                Text(summary.expense.formattedCurrency)
                    .font(DesignSystem.Typography.amount.monospacedDigit())
                    .foregroundStyle(DesignSystem.textPrimary)
            }

            HStack(spacing: 9) {
                summarySecondaryMetric(
                    title: "\(filterState.dateFilter.metricPrefix)收入",
                    value: summary.hasHiddenIncome ? privacyLock.maskedText : summary.income.formattedCurrency,
                    color: DesignSystem.textPrimary
                )
                summarySecondaryMetric(
                    title: "\(filterState.dateFilter.metricPrefix)结余",
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
        switch filterState.dateFilter {
        case .today:
            return now.fullDateString
        case .thisWeek, .thisMonth, .payCycle, .custom:
            guard let range = filterState.dateFilter.dateRange(
                referenceDate: now,
                payday: payday,
                customStart: filterState.customStartDate,
                customEnd: filterState.customEndDate,
                calendar: calendar
            ) else { return filterState.dateFilter.rawValue }
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

    func ledgerBudgetCard(_ reminder: BudgetReminder) -> some View {
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

    func transactionList(_ presentation: LedgerPresentation) -> some View {
        LazyVStack(spacing: 4) {
            if presentation.dayGroups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: filterState.hasActiveFilters || !filterState.searchText.isEmpty ? "line.3.horizontal.decrease.circle" : "tray")
                        .font(.system(size: 40))
                        .foregroundStyle(DesignSystem.textTertiary)
                    if filterState.hasActiveFilters || !filterState.searchText.isEmpty {
                        Text("没有匹配的交易记录")
                            .font(.subheadline)
                            .foregroundStyle(DesignSystem.textTertiary)
                        Text("试试调整筛选条件或搜索关键词")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.textTertiary)
                        if filterState.hasActiveFilters {
                            Button("清除筛选") {
                                withAnimation(reduceMotion ? nil : DesignSystem.standardAnimation) {
                                    filterState.clearAdvancedFilters()
                                    filterState.searchText = ""
                                    filterState.debouncedSearchText = ""
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
                        transactionRow(transaction)
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
                    Task { await loadNextPage() }
                } label: {
                    VStack(spacing: 4) {
                        Text("继续加载")
                            .font(.subheadline.weight(.semibold))
                        Text("已显示 \(presentation.visibleTransactionCount) / \(presentation.totalTransactionCount) 笔")
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

    private func transactionRow(_ transaction: Transaction) -> some View {
        let isSelected = selectedIds.contains(transaction.id)

        return HStack(spacing: 0) {
            if isSelecting {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.2)) {
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
                        .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(isSelected ? "取消选择交易" : "选择交易")
                    .accessibilityIdentifier("ledger.select.\(transaction.id.uuidString)")
            }

            Button {
                if isSelecting {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.2)) {
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
            } label: {
                TransactionRow(
                    transaction: transaction,
                    revealsPrivateIncome: privacyLock.isUnlocked,
                    hidesIncome: privacyLock.hidesSensitiveAmounts
                )
            }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelecting ? "选择交易" : (isIncomeHidden(transaction) ? "隐私收入，验证后查看" : "编辑交易"))
                .accessibilityHint(isSelecting ? "双击切换选择状态" : "双击打开编辑")
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
                            withAnimation(reduceMotion ? nil : DesignSystem.standardAnimation) {
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
                            withAnimation(reduceMotion ? nil : DesignSystem.standardAnimation) {
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

    // MARK: - 删除撤销 Toast

    var undoDeleteToast: some View {
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
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
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

    func batchActionBar(transactions: [Transaction]) -> some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                batchDeleteSelected()
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
                withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
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
}
