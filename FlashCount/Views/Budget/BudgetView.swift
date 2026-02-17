import SwiftUI
import SwiftData

/// 预算管理页面
struct BudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ledger.sortOrder) private var ledgers: [Ledger]
    @Query(sort: \Budget.createdAt) private var allBudgets: [Budget]
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]

    @State private var selectedLedger: Ledger?
    @State private var showAddBudget = false

    private var currentBudget: Budget? {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        return allBudgets.first { b in
            b.year == year && b.month == month
            && b.ledger?.id == selectedLedger?.id
            && b.categoryId == nil
        }
    }

    private var monthlySpent: Decimal {
        let calendar = Calendar.current
        let now = Date()
        return allTransactions
            .filter { $0.isExpense && calendar.isDate($0.date, equalTo: now, toGranularity: .month) && $0.ledger?.id == selectedLedger?.id }
            .reduce(0) { $0 + $1.amount }
    }

    private var analysis: BudgetAnalysis? {
        guard let budget = currentBudget else { return nil }
        return BudgetAnalyzer.analyze(budgetLimit: budget.monthlyLimit, totalSpent: monthlySpent)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: DesignSystem.sectionSpacing) {
                        budgetLedgerPicker
                        if let analysis = analysis {
                            BudgetOverviewCard(analysis: analysis)
                            BudgetAlertCard(analysis: analysis)
                            BudgetMetricsGrid(analysis: analysis)
                        } else {
                            noBudgetPlaceholder
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("预算")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showAddBudget) {
                AddBudgetView(ledger: selectedLedger)
            }
            .onAppear {
                if selectedLedger == nil {
                    selectedLedger = ledgers.first(where: { $0.isDefault }) ?? ledgers.first
                }
            }
        }
    }

    private var budgetLedgerPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ledgers, id: \.id) { ledger in
                    Button {
                        withAnimation(.spring(response: 0.3)) { selectedLedger = ledger }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: ledger.icon).font(.caption)
                            Text(ledger.name).font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(selectedLedger?.id == ledger.id ? Color(hex: ledger.colorHex).opacity(0.2) : .white.opacity(0.06))
                        .foregroundStyle(selectedLedger?.id == ledger.id ? Color(hex: ledger.colorHex) : .white.opacity(0.5))
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var noBudgetPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.pie").font(.system(size: 50)).foregroundStyle(.white.opacity(0.2))
            Text("暂未设置预算").font(.headline).foregroundStyle(.white.opacity(0.5))
            Text("设置月度预算，智能预警你的消费进度").font(.subheadline).foregroundStyle(.white.opacity(0.3)).multilineTextAlignment(.center)
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
