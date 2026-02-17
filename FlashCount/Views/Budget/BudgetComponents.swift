import SwiftUI

/// 预算概览卡片 - 进度条 + 百分比
struct BudgetOverviewCard: View {
    let analysis: BudgetAnalysis

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(Date().monthYearString).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(analysis.alertLevel.emoji).font(.title3)
            }
            VStack(spacing: 8) {
                HStack {
                    Text("已花费").font(.caption).foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text("\(analysis.totalSpent.formattedCurrency) / \(analysis.budgetLimit.formattedCurrency)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.1)).frame(height: 12)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(progressGradient)
                            .frame(width: min(geo.size.width * CGFloat(min(analysis.usagePercent, 1.0)), geo.size.width), height: 12)
                            .animation(.spring(response: 0.8), value: analysis.usagePercent)
                    }
                }
                .frame(height: 12)
                HStack {
                    Text("\(Int(min(analysis.usagePercent, 9999) * 100))%").font(.caption2.monospacedDigit()).foregroundStyle(alertColor)
                    Spacer()
                    Text("预计: \(analysis.projectedTotal.formattedCurrency)").font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .glassCard()
    }

    private var progressGradient: LinearGradient {
        switch analysis.alertLevel {
        case .healthy: return DesignSystem.incomeGradient
        case .warning: return DesignSystem.warningGradient
        case .danger: return DesignSystem.dangerGradient
        }
    }

    private var alertColor: Color {
        switch analysis.alertLevel {
        case .healthy: return DesignSystem.incomeColor
        case .warning: return DesignSystem.warningColor
        case .danger: return DesignSystem.dangerColor
        }
    }
}

/// 预警消息卡片
struct BudgetAlertCard: View {
    let analysis: BudgetAnalysis

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: alertIcon).font(.title2).foregroundStyle(alertColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(analysis.alertLevel.rawValue).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(analysis.alertMessage).font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
        }
        .padding()
        .background(alertColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius).stroke(alertColor.opacity(0.3), lineWidth: 1))
    }

    private var alertIcon: String {
        switch analysis.alertLevel {
        case .healthy: return "checkmark.shield.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "flame.fill"
        }
    }

    private var alertColor: Color {
        switch analysis.alertLevel {
        case .healthy: return DesignSystem.incomeColor
        case .warning: return DesignSystem.warningColor
        case .danger: return DesignSystem.dangerColor
        }
    }
}

/// 预算详细指标网格
struct BudgetMetricsGrid: View {
    let analysis: BudgetAnalysis

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metricCard(title: "日均消费", value: analysis.dailyAverage.formattedCurrency, icon: "chart.bar.fill", color: "#778BEB")
            metricCard(title: "每日可花", value: analysis.dailyAllowance.formattedCurrency, icon: "wallet.pass.fill",
                       color: analysis.alertLevel == .danger ? "#FF4757" : "#2ED573")
            metricCard(title: "剩余预算", value: analysis.remainingBudget.formattedCurrency, icon: "banknote.fill",
                       color: analysis.remainingBudget >= 0 ? "#4ECDC4" : "#FF6B6B")
            metricCard(title: "剩余天数", value: "\(analysis.daysRemaining) 天", icon: "calendar", color: "#FFA502")
        }
    }

    private func metricCard(title: String, value: String, icon: String, color: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Image(systemName: icon).font(.caption).foregroundStyle(Color(hex: color)); Spacer() }
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(.white)
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.5))
        }
        .glassCard()
    }
}

/// 添加预算
struct AddBudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let ledger: Ledger?
    @State private var amountText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text(Date().monthYearString).font(.subheadline).foregroundStyle(.white.opacity(0.5))
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("¥").font(.title2).foregroundStyle(.white.opacity(0.6))
                            TextField("0", text: $amountText).keyboardType(.decimalPad)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .monospacedDigit().foregroundStyle(.white).multilineTextAlignment(.center)
                        }.padding(.vertical, 20)
                        Text("月度预算上限").font(.caption).foregroundStyle(.white.opacity(0.4))
                    }
                    HStack(spacing: 12) {
                        ForEach(["3000", "5000", "8000", "10000"], id: \.self) { amount in
                            Button { amountText = amount } label: {
                                Text("¥\(amount)").font(.caption.weight(.medium))
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(.white.opacity(0.06)).foregroundStyle(.white.opacity(0.6)).clipShape(Capsule())
                            }
                        }
                    }
                    Spacer()
                }.padding()
            }
            .navigationTitle("设置预算").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() }.foregroundStyle(.white.opacity(0.7)) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { saveBudget() }.disabled(amountText.isEmpty).foregroundStyle(DesignSystem.primaryColor)
                }
            }
        }
    }

    private func saveBudget() {
        guard let amount = Decimal(string: amountText), amount > 0 else { return }
        let cal = Calendar.current; let now = Date()
        let budget = Budget(monthlyLimit: amount, year: cal.component(.year, from: now), month: cal.component(.month, from: now), ledger: ledger)
        modelContext.insert(budget); try? modelContext.save(); dismiss()
    }
}
