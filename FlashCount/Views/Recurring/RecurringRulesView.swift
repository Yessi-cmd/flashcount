import SwiftUI
import SwiftData

/// 周期性规则管理页面
struct RecurringRulesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecurringRule.createdAt, order: .reverse) private var rules: [RecurringRule]
    @State private var showAddRule = false

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        if rules.isEmpty { emptyState }
                        else {
                            ForEach(rules, id: \.id) { rule in
                                ruleCard(rule)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("周期账单")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddRule = true } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(DesignSystem.primaryColor)
                    }
                }
            }
            .sheet(isPresented: $showAddRule) { AddRecurringRuleView() }
        }
    }

    private func ruleCard(_ rule: RecurringRule) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(hex: rule.category?.colorHex ?? "#667EEA").opacity(0.15)).frame(width: 44, height: 44)
                Image(systemName: rule.category?.icon ?? "repeat").font(.title3)
                    .foregroundStyle(Color(hex: rule.category?.colorHex ?? "#667EEA"))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(rule.title).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                    if !rule.isActive {
                        Text("已暂停").font(.caption2).foregroundStyle(.white.opacity(0.4))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.white.opacity(0.06)).clipShape(Capsule())
                    }
                }
                Text("\(rule.frequency.rawValue) · 下次: \(rule.nextDueDate.shortDateString)")
                    .font(.caption).foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(rule.amount.formattedCurrency)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(rule.isExpense ? DesignSystem.expenseColor : DesignSystem.incomeColor)
                // 暂停/恢复按钮
                Button {
                    rule.isActive.toggle()
                    try? modelContext.save()
                } label: {
                    Image(systemName: rule.isActive ? "pause.circle" : "play.circle")
                        .font(.caption).foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .glassCard()
        .opacity(rule.isActive ? 1 : 0.6)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "repeat").font(.system(size: 50)).foregroundStyle(.white.opacity(0.2))
            Text("暂无周期账单").font(.headline).foregroundStyle(.white.opacity(0.5))
            Text("添加房租、订阅等固定开支，自动生成记录").font(.subheadline).foregroundStyle(.white.opacity(0.3)).multilineTextAlignment(.center)
            Button { showAddRule = true } label: {
                Text("添加周期账单").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 12).background(DesignSystem.primaryGradient).clipShape(Capsule())
            }
        }.padding(.vertical, 60)
    }
}
