import SwiftUI
import SwiftData

/// 账本主页面 - 展示当前账本的交易列表和统计。
/// 按职责拆分：筛选状态在 `LedgerFilterState`，呈现模型在
/// `LedgerPresentation.swift`，区块视图在 `LedgerSections.swift`，
/// 分页与删除动作在 `LedgerActions.swift`。
struct LedgerView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @EnvironmentObject var privacyLock: PrivacyLockService
    @AppStorage("payday") var payday = 1
    @AppStorage(WeekendBudgetPreferences.storageKey) var weekendBudgetMultiplierPercent = WeekendBudgetPreferences.defaultRawValue
    @Query var allTransactions: [Transaction]
    @Query(sort: \Budget.createdAt) var allBudgets: [Budget]

    @Query(
        filter: #Predicate<Category> { !$0.isArchived },
        sort: \Category.sortOrder
    ) var allCategories: [Category]

    // 行动中心 badge 需要的原始数据。快照本身在 .task 里算，不放进 body：
    // pendingOccurrences 会实际推演周期规则，跟着每次渲染跑太贵。
    @Query(sort: \RecurringRule.nextDueDate) var recurringRules: [RecurringRule]
    @Query var recurringOccurrences: [RecurringOccurrence]
    @Query(sort: \InstallmentBill.createdAt, order: .reverse) var installmentBills: [InstallmentBill]
    @Query(sort: \Reminder.dueDate) var reminderModels: [Reminder]
    @Query(sort: \CashPoolItem.sortOrder) var cashPoolItems: [CashPoolItem]
    @Query(sort: \CashPoolState.updatedAt, order: .reverse) var cashPoolStates: [CashPoolState]

    @State var filterState = LedgerFilterState()
    @State var pendingActionCount = 0

    @State var showAddTransaction = false
    @State var editingTransaction: Transaction?
    @State var showCustomDatePicker = false
    @State var showCalendar = false
    @State var showSettings = false
    @State var showReminders = false
    @State var showActionCenter = false
    @State var showFilterSheet = false
    @State var deleteError: String?
    @State var undoInfo: DeletedTransactionSnapshot?
    @State var undoDismissTask: Task<Void, Never>?
    @State var undoDismissToken: UUID?
    @State var isSelecting = false
    @State var selectedIds = Set<UUID>()
    @State var selectAllTask: Task<Void, Never>?
    @State var selectAllLoadToken: UUID?
    @State var batchDeleteError: String?
    @State var loadedTransactions: [Transaction] = []
    @State var totalTransactionCount = 0
    @State var ledgerSummary: LedgerSummary?
    @State var ledgerPresentation = LedgerPresentation.empty
    @State var loadedLedgerQueryID: String?
    @State var ledgerDataRevision = 0
    @State var isLoadingPage = false
    @State var pageLoadToken: UUID?

    let transactionPageSize = 200
    let recentCutoff: Date

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

    var presentationTransactions: [Transaction] {
        loadedTransactions
    }

    var displayedMonthlySummary: LedgerPresentation.MonthlySummary {
        guard let ledgerSummary else { return ledgerPresentation.monthlySummary }
        return LedgerPresentation.MonthlySummary(
            expense: ledgerSummary.expense,
            income: ledgerSummary.income,
            hasHiddenIncome: ledgerSummary.hasHiddenIncome
        )
    }

    var budgetReminder: BudgetReminder? {
        BudgetReminderService.reminder(
            budgets: allBudgets,
            transactions: allTransactions,
            ledger: nil,
            payday: payday,
            weekendMultiplier: WeekendBudgetPreferences.multiplier(for: weekendBudgetMultiplierPercent)
        )
    }

    /// The Action Center count depends on model values, not just collection sizes.
    /// Keep this digest aligned with the same inputs used by the badge snapshot.
    var actionCenterDigest: Int {
        LocalActionCenterDigest.make(
            budgets: allBudgets,
            transactions: allTransactions,
            categories: allCategories,
            recurringRules: recurringRules,
            occurrences: recurringOccurrences,
            installmentBills: installmentBills,
            reminders: reminderModels,
            cashPoolItems: cashPoolItems,
            cashPoolStates: cashPoolStates,
            payday: payday,
            weekendBudgetMultiplierPercent: weekendBudgetMultiplierPercent,
            dismissedSuggestionFingerprints: UserDefaultsRecurringSuggestionDismissalStore().load()
        )
    }

    func isIncomeHidden(_ transaction: Transaction) -> Bool {
        PrivacyVisibilityPolicy.hidesIncome(
            isExpense: transaction.isExpense,
            isUnlocked: privacyLock.isUnlocked
        )
    }

    var body: some View {
        let presentation = ledgerPresentation

        return NavigationStack {
            ZStack {
                AmbientBackground(accent: DesignSystem.primaryColor)

                ScrollView {
                    // 搜索与日期条做成 pinned section header：初次进入仍排在结论之后，
                    // 滚到列表时自动吸顶——它们恰恰是浏览列表时才想调的东西，
                    // 过去一滚就全部滚出屏幕。
                    LazyVStack(spacing: DesignSystem.sectionSpacing, pinnedViews: [.sectionHeaders]) {
                        // B 方向先呈现核心结论，再提供搜索与筛选工具。
                        monthlySummaryCard(displayedMonthlySummary)

                        if let budgetReminder {
                            ledgerBudgetCard(budgetReminder)
                        }

                        Section {
                            ledgerBody(presentation)
                        } header: {
                            stickyFilterHeader
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
                            cancelSelectAllTask()
                            withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
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

                            Button(selectedIds.count == presentation.totalTransactionCount ? "取消全选" : "全选") {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                                    if selectedIds.count == presentation.totalTransactionCount {
                                        cancelSelectAllTask()
                                        selectedIds.removeAll()
                                    } else {
                                        selectAllMatchingTransactions()
                                    }
                                }
                            }
                            .foregroundStyle(DesignSystem.primaryColor)
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                                showCalendar.toggle()
                            }
                        } label: {
                            Image(systemName: showCalendar ? "list.bullet" : "calendar")
                                .foregroundStyle(DesignSystem.textSecondary)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(showCalendar ? "显示列表" : "显示日历")
                        .accessibilityIdentifier("ledger.calendarToggle")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        // 5 个并排按钮在 iOS 26 工具栏放不下，会被系统折叠成
                        // 不可控的 More 菜单；保留筛选与行动中心直达，
                        // 其余次级动作收进自己的「更多」菜单。
                        HStack(spacing: 8) {
                            Button {
                                showFilterSheet = true
                            } label: {
                                HStack(spacing: 2) {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.subheadline)
                                        .foregroundStyle(filterState.hasActiveFilters || filterState.hasCustomSort ? DesignSystem.primaryColor : DesignSystem.textSecondary)
                                    if filterState.hasActiveFilters {
                                        Text("\(filterState.activeFilterCount)")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 16, height: 16)
                                            .background(DesignSystem.primaryColor)
                                            .clipShape(Circle())
                                    }
                                }
                                .frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel("筛选与排序，当前\(filterState.sortDirection.detail(for: filterState.sortField))")
                            .accessibilityIdentifier("ledger.filter")

                            // 常亮的警示色图标很快会被脱敏，真有急事时也不会被看见。
                            // 有待办才亮起并给出数量，没有就退成普通灰。
                            Button {
                                showActionCenter = true
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: pendingActionCount > 0 ? "bolt.badge.clock.fill" : "bolt.badge.clock")
                                        .foregroundStyle(pendingActionCount > 0 ? DesignSystem.warningColor : DesignSystem.textSecondary)
                                        .frame(width: 44, height: 44)

                                    if pendingActionCount > 0 {
                                        Text(pendingActionCount > 99 ? "99+" : "\(pendingActionCount)")
                                            .font(.caption2.weight(.bold))
                                            .monospacedDigit()
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 4)
                                            .frame(minWidth: 16, minHeight: 16)
                                            .background(DesignSystem.dangerColor)
                                            .clipShape(Capsule())
                                            .offset(x: 2, y: 2)
                                    }
                                }
                            }
                            .accessibilityLabel(
                                pendingActionCount > 0
                                    ? "本地行动中心，\(pendingActionCount) 项待处理"
                                    : "本地行动中心，暂无待处理"
                            )
                            .accessibilityIdentifier("ledger.actionCenter")

                            Menu {
                                Button {
                                    withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                                        isSelecting = true
                                    }
                                } label: {
                                    Label("批量选择", systemImage: "checkmark.circle")
                                }
                                .accessibilityIdentifier("ledger.batchSelect")

                                Button {
                                    showReminders = true
                                } label: {
                                    Label("提醒事项", systemImage: "bell.badge.fill")
                                }
                                .accessibilityIdentifier("ledger.reminders")

                                Button {
                                    showSettings = true
                                } label: {
                                    Label("设置", systemImage: "gearshape")
                                }
                                .accessibilityIdentifier("ledger.settings")
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(DesignSystem.textSecondary)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("更多操作")
                            .accessibilityIdentifier("ledger.more")
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
            .sheet(isPresented: $showActionCenter) {
                ActionCenterView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showFilterSheet) {
                FilterSheetView(
                    typeFilter: $filterState.typeFilter,
                    categoryFilterId: $filterState.categoryFilterId,
                    minAmountText: $filterState.minAmountText,
                    maxAmountText: $filterState.maxAmountText,
                    sortField: $filterState.sortField,
                    sortDirection: $filterState.sortDirection
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
            .task(id: filterState.searchText) {
                // 防抖：用户停止输入 300ms 后再执行搜索过滤
                let query = filterState.searchText
                do {
                    try await Task.sleep(for: .milliseconds(300))
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
                guard LedgerSearchQueryGate.accepts(
                    query: query,
                    latestQuery: filterState.searchText,
                    isCancelled: Task.isCancelled
                ) else { return }
                filterState.debouncedSearchText = query
            }
            .task(id: ledgerQueryID) {
                await loadFirstPage()
            }
            .task(id: actionCenterDigest) {
                await refreshPendingActionCount()
            }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                ledgerDataRevision &+= 1
            }
            .onChange(of: filterState.debouncedSearchText) { resetLedgerPage() }
            .onChange(of: filterState.dateFilter) { resetLedgerPage() }
            .onChange(of: filterState.typeFilter) { resetLedgerPage() }
            .onChange(of: filterState.categoryFilterId) { resetLedgerPage() }
            .onChange(of: filterState.minAmountText) { resetLedgerPage() }
            .onChange(of: filterState.maxAmountText) { resetLedgerPage() }
            .onChange(of: filterState.customStartDate) { resetLedgerPage() }
            .onChange(of: filterState.customEndDate) { resetLedgerPage() }
            .onChange(of: filterState.sortField) { resetLedgerPage() }
            .onChange(of: filterState.sortDirection) { resetLedgerPage() }
            .onDisappear {
                cancelSelectAllTask()
                undoDismissTask?.cancel()
                undoDismissTask = nil
                undoDismissToken = nil
                undoInfo = nil
            }
        }
    }
}
