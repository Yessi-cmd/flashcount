import SwiftUI
import SwiftData

/// 本地行动中心：把预算风险、待扣款、分期、周期建议与未完成提醒集中到一处。
/// 数据全部来自 `LocalActionCenterService`，账本页图标上的 badge 必须与这里同口径。
struct ActionCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var privacyLock: PrivacyLockService

    @Query(sort: \Budget.createdAt) private var budgets: [Budget]
    @Query(
        filter: #Predicate<Transaction> { $0.isExpense == true },
        sort: \Transaction.date,
        order: .reverse
    ) private var expenseTransactions: [Transaction]
    @Query(sort: \RecurringRule.nextDueDate) private var recurringRules: [RecurringRule]
    @Query private var occurrences: [RecurringOccurrence]
    @Query(sort: \InstallmentBill.createdAt, order: .reverse) private var installmentBills: [InstallmentBill]
    @Query(sort: \Reminder.dueDate) private var reminderModels: [Reminder]
    @Query(sort: \CashPoolItem.sortOrder) private var cashPoolItems: [CashPoolItem]
    @Query(sort: \CashPoolState.updatedAt, order: .reverse) private var cashPoolStates: [CashPoolState]

    @AppStorage("payday") private var payday = 1
    @AppStorage(WeekendBudgetPreferences.storageKey)
    private var weekendBudgetMultiplierPercent = WeekendBudgetPreferences.defaultRawValue

    @State private var dismissedSuggestionFingerprints: Set<String> = []
    @State private var presentedDestination: LocalActionDestination?

    private let suggestionDismissalStore = UserDefaultsRecurringSuggestionDismissalStore()

    private var pendingBackfill: [RecurringOccurrencePreview] {
        RecurringOccurrenceService(modelContext: modelContext).pendingOccurrences(
            rules: recurringRules,
            occurrences: occurrences,
            maxOccurrences: 120
        )
    }

    private func makeSnapshot() -> LocalActionCenterSnapshot {
        LocalActionCenterService.snapshot(
            budgets: budgets,
            transactions: expenseTransactions,
            recurringRules: recurringRules,
            occurrences: occurrences,
            pendingBackfill: pendingBackfill,
            installmentBills: installmentBills,
            reminders: reminderModels.map(\.item),
            cashPoolItems: cashPoolItems,
            cashPoolState: cashPoolStates.first,
            dismissedSuggestionFingerprints: dismissedSuggestionFingerprints,
            payday: payday,
            weekendMultiplier: WeekendBudgetPreferences.multiplier(
                for: weekendBudgetMultiplierPercent
            )
        )
    }

    var body: some View {
        let snapshot = makeSnapshot()

        return NavigationStack {
            ZStack {
                AmbientBackground(accent: DesignSystem.warningColor)

                ScrollView {
                    LazyVStack(spacing: DesignSystem.sectionSpacing) {
                        ActionCenterSummaryView(snapshot: snapshot)

                        if snapshot.isEmpty {
                            ContentUnavailableView(
                                "暂无待处理事项",
                                systemImage: "checkmark.circle",
                                description: Text("新的预算、现金流、扣款、分期或提醒风险出现后，会在这里集中展示。")
                            )
                            .frame(maxWidth: .infinity, minHeight: 260)
                        } else {
                            ForEach(snapshot.sections) { section in
                                ActionCenterSectionView(
                                    section: section,
                                    hidesSensitiveAmounts: PrivacyVisibilityPolicy.hidesAssets(
                                        isUnlocked: privacyLock.isUnlocked
                                    ),
                                    onSelect: open,
                                    onShowAll: openDestination
                                )
                            }
                        }
                    }
                    .padding()
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("本地行动中心")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    PrivacyVisibilityButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成", action: dismiss.callAsFunction)
                        .foregroundStyle(DesignSystem.primaryColor)
                }
            }
            .sheet(item: $presentedDestination, content: destinationView)
            .task {
                loadDismissedSuggestions()
            }
            .onChange(of: presentedDestination) { _, destination in
                if destination == nil {
                    loadDismissedSuggestions()
                }
            }
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: LocalActionDestination) -> some View {
        switch destination {
        case .budget:
            BudgetView()
        case .cashFlowForecast:
            NavigationStack {
                CashFlowForecastView()
            }
        case .recurringRules:
            RecurringRulesView()
        case .installmentBills:
            InstallmentBillView()
        case .reminders:
            ReminderView()
        }
    }

    private func open(_ item: LocalActionItem) {
        openDestination(item.destination)
    }

    private func openDestination(_ destination: LocalActionDestination) {
        presentedDestination = destination
    }

    private func loadDismissedSuggestions() {
        dismissedSuggestionFingerprints = suggestionDismissalStore.load()
    }
}
