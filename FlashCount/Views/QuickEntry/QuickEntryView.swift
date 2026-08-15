import SwiftUI
import SwiftData

/// 极速记账页面 - 打开即可记账，3秒完成。
/// 区块视图在 `QuickEntrySections.swift`，输入与保存逻辑在 `QuickEntryLogic.swift`。
struct QuickEntryView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @EnvironmentObject var feedback: QuickEntryFeedbackCenter
    @AppStorage("payday") var payday = 1
    @AppStorage(WeekendBudgetPreferences.storageKey) var weekendBudgetMultiplierPercent = WeekendBudgetPreferences.defaultRawValue

    @Query(sort: \Ledger.sortOrder) var ledgers: [Ledger]
    @Query(
        filter: #Predicate<Category> { $0.isExpense == true && $0.isArchived == false },
        sort: \Category.sortOrder
    ) var expenseCategories: [Category]
    @Query(
        filter: #Predicate<Category> { $0.isExpense == false && $0.isArchived == false },
        sort: \Category.sortOrder
    ) var incomeCategories: [Category]
    @Query(sort: \Budget.createdAt) var allBudgets: [Budget]
    @Query var recentTransactions: [Transaction]

    @State var amountInput = QuickEntryAmountInput()
    @State var amountError: MoneyValidationError?
    @State var isExpense = true
    @State var selectedCategory: Category?
    @State var selectedLedger: Ledger?
    @State var note = ""
    @State var selectedDate = Date()
    @State var showDatePicker = false
    @State var showNote = false
    @State var saveError: String?
    @State var wheelCategory: Category?
    @State var wheelSourceFrame: CGRect?
    @State var showAllCategories = false
    @State var showTemplateManager = false
    @State var editingTemplate: TransactionTemplate?
    @State var isSaving = false
    @State var dailyBudgetOverride: Bool?
    /// 收支切换会换掉整套分类，所以两侧各记住用户自己选过的那一个：
    /// 误触键盘上的「收入」再切回来，不该把刚选好的分类冲掉。
    @State var rememberedExpenseCategory: Category?
    @State var rememberedIncomeCategory: Category?
    @Namespace var typeSelectionNamespace

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

    var currentCategories: [Category] {
        isExpense ? expenseCategories : incomeCategories
    }

    var canSubmitAmount: Bool { amountInput.canSubmit }

    /// 输入中的金额（含「+」已累加部分）。解析失败时按无草稿处理，
    /// 预算条仍显示当前剩余，不会因为半个输入状态闪烁。
    var currentDraftAmount: Decimal? {
        try? amountInput.resolved().get()
    }

    /// 金额下方实时预算提示。支出且设置了当前周期总预算时才有。
    var budgetHint: QuickEntryBudgetHint? {
        QuickEntryBudgetHintCalculator.makeHint(
            budgets: allBudgets,
            transactions: recentTransactions,
            ledger: nil,
            referenceDate: selectedDate,
            payday: payday,
            weekendMultiplier: WeekendBudgetPreferences.multiplier(for: weekendBudgetMultiplierPercent),
            draft: QuickEntryBudgetDraft(
                amount: currentDraftAmount,
                isExpense: isExpense,
                category: selectedCategory,
                dailyBudgetOverride: dailyBudgetOverride
            )
        )
    }

    /// 日期不是今天时，保存按钮和提示条都要说清这是补录——
    /// 日期控件本身太安静，看漏了就会把今天的账记到别的日子。
    var isBackdated: Bool {
        !Calendar.current.isDateInToday(selectedDate)
    }

    var rootCategories: [Category] {
        Category.rootCategories(from: currentCategories, isExpense: isExpense)
    }

    var recentCategories: [Category] {
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
                    .animation(reduceMotion ? nil : DesignSystem.standardAnimation, value: isExpense)

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
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                .modifier(
                    QuickEntryBottomBar(
                        barContent: bottomControls
                            .softReveal(delay: 0.18, distance: 18)
                    )
                )
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
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(showNote ? "隐藏备注" : "添加备注")
                        .accessibilityIdentifier("quickEntry.noteToggle")
                    }
                }
            }
            .overlay {
                if let wheelCategory {
                    categoryWheel(for: wheelCategory)
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
}

/// 键盘高度远大于普通工具栏，始终为其预留安全区，避免滚动内容透到按键下方。
struct QuickEntryBottomBar<BarContent: View>: ViewModifier {
    let barContent: BarContent

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            barContent
        }
    }
}
