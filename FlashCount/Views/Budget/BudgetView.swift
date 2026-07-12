import SwiftUI
import SwiftData

/// 预算管理页面
struct BudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("payday") private var payday = 1
    @Query(sort: \Budget.createdAt) private var allBudgets: [Budget]
    @Query private var recentTransactions: [Transaction]
    @Query(
        filter: #Predicate<Category> { $0.isExpense == true && $0.isArchived == false },
        sort: \Category.sortOrder
    ) private var expenseCategories: [Category]

    @State private var showAddBudget = false
    @State private var showBudgetScope = false

    init() {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: Date())) ?? .distantPast
        _recentTransactions = Query(
            filter: #Predicate<Transaction> { $0.date >= cutoff },
            sort: \Transaction.date,
            order: .reverse
        )
    }

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
            transactions: recentTransactions,
            ledger: nil,
            payday: payday
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(accent: DesignSystem.incomeColor)
                ScrollView {
                    VStack(spacing: DesignSystem.sectionSpacing) {
                        if let reminder {
                            BudgetOverviewCard(analysis: reminder.analysis)
                            BudgetAlertCard(reminder: reminder)
                            dailyBudgetScopeCard
                            BudgetMetricsGrid(analysis: reminder.analysis)
                        } else {
                            noBudgetPlaceholder
                            dailyBudgetScopeCard
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
            .sheet(isPresented: $showBudgetScope) {
                DailyBudgetScopeView()
            }
        }
    }

    private var noBudgetPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.pie").font(.system(size: 50)).foregroundStyle(DesignSystem.textTertiary)
            Text("暂未设置预算").font(.headline).foregroundStyle(DesignSystem.textPrimary)
            Text("输入本发薪周期日常消费预算，按剩余天数提醒每日可花").font(.subheadline).foregroundStyle(DesignSystem.textSecondary).multilineTextAlignment(.center)
            Button {
                showAddBudget = true
            } label: {
                Text("设置预算").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(DesignSystem.primaryColor)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        }
        .padding(.vertical, 60)
    }

    private var dailyBudgetScopeCard: some View {
        Button {
            showBudgetScope = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "scope")
                    .font(.headline)
                    .foregroundStyle(DesignSystem.primaryColor)
                    .frame(width: 38, height: 38)
                    .background(DesignSystem.primaryColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("日常预算范围")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.textPrimary)
                    Text("当前纳入 \(expenseCategories.filter { BudgetScope.includesCategory($0) }.count) 个分类 · 可自定义")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textSecondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.textTertiary)
            }
            .padding(DesignSystem.cardPadding)
            .background(DesignSystem.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius, style: .continuous)
                    .stroke(DesignSystem.primaryColor.opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(PressableButtonStyle())
    }
}
