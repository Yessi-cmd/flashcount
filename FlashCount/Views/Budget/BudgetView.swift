import SwiftUI
import SwiftData

/// 预算管理页面
struct BudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("payday") private var payday = 1
    @Query(sort: \Budget.createdAt) private var allBudgets: [Budget]
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]

    @State private var showAddBudget = false

    private var currentBudget: Budget? {
        BudgetReminderService.currentBudget(
            in: allBudgets,
            ledger: nil,
            payday: payday
        )
    }

    private var reminder: BudgetReminder? {
        BudgetReminderService.reminder(
            budgets: allBudgets,
            transactions: allTransactions,
            ledger: nil,
            payday: payday
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: DesignSystem.sectionSpacing) {
                        if let reminder {
                            BudgetOverviewCard(analysis: reminder.analysis)
                            BudgetAlertCard(reminder: reminder)
                            BudgetMetricsGrid(analysis: reminder.analysis)
                        } else {
                            noBudgetPlaceholder
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("预算")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddBudget = true
                    } label: {
                        Label(currentBudget == nil ? "设置预算" : "调整预算", systemImage: currentBudget == nil ? "plus" : "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $showAddBudget) {
                AddBudgetView(ledger: nil, existingBudget: currentBudget, payday: payday)
            }
        }
    }

    private var noBudgetPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.pie").font(.system(size: 50)).foregroundStyle(DesignSystem.textTertiary)
            Text("暂未设置预算").font(.headline).foregroundStyle(DesignSystem.textPrimary)
            Text("输入本发薪周期日常消费预算，按剩余天数提醒每日可花").font(.subheadline).foregroundStyle(DesignSystem.textSecondary).multilineTextAlignment(.center)
            Text(BudgetScope.description)
                .font(.caption)
                .foregroundStyle(DesignSystem.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                showAddBudget = true
            } label: {
                Text("设置预算").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(DesignSystem.primaryGradient).clipShape(Capsule())
            }
        }
        .padding(.vertical, 60)
    }
}
