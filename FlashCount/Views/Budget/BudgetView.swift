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

    private var categoryBudgetSnapshots: [CategoryBudgetSnapshot] {
        CategoryBudgetService.snapshots(
            budgets: allBudgets,
            transactions: recentTransactions,
            categories: expenseCategories,
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
                            categoryBudgetCard
                            BudgetMetricsGrid(analysis: reminder.analysis)
                        } else {
                            noBudgetPlaceholder
                            dailyBudgetScopeCard
                            categoryBudgetCard
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

    private var categoryBudgetCard: some View {
        NavigationLink {
            CategoryBudgetsView()
        } label: {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.headline)
                        .foregroundStyle(DesignSystem.primaryColor)
                        .frame(width: 38, height: 38)
                        .background(DesignSystem.primaryColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("分类预算")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DesignSystem.textPrimary)
                        Text(categoryBudgetSubtitle)
                            .font(.caption)
                            .foregroundStyle(DesignSystem.textSecondary)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignSystem.textTertiary)
                }

                ForEach(categoryBudgetSnapshots.prefix(3)) { snapshot in
                    HStack(spacing: 8) {
                        Image(systemName: snapshot.category.icon)
                            .foregroundStyle(Color(hex: snapshot.category.colorHex))
                            .frame(width: 20)
                        Text(snapshot.category.name)
                            .font(.caption)
                            .foregroundStyle(DesignSystem.textSecondary)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(DesignSystem.dividerColor)
                                Capsule()
                                    .fill(categoryBudgetColor(snapshot.alertLevel))
                                    .frame(width: proxy.size.width * min(max(snapshot.analysis.usagePercent, 0), 1))
                            }
                        }
                        .frame(height: 6)
                        Text("\(Int(min(snapshot.analysis.usagePercent, 99.99) * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(categoryBudgetColor(snapshot.alertLevel))
                            .frame(width: 38, alignment: .trailing)
                    }
                }
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

    private var categoryBudgetSubtitle: String {
        guard !categoryBudgetSnapshots.isEmpty else { return "为餐饮、购物等分类设置独立上限" }
        let alerts = categoryBudgetSnapshots.filter { $0.alertLevel != .healthy }.count
        return alerts == 0
            ? "已设置 \(categoryBudgetSnapshots.count) 项 · 当前均健康"
            : "已设置 \(categoryBudgetSnapshots.count) 项 · \(alerts) 项需要注意"
    }

    private func categoryBudgetColor(_ level: BudgetAlertLevel) -> Color {
        switch level {
        case .healthy: return DesignSystem.incomeColor
        case .warning: return DesignSystem.warningColor
        case .danger: return DesignSystem.dangerColor
        }
    }
}
