import SwiftUI
import SwiftData

/// 预算概览卡片 - 进度条 + 百分比
struct BudgetOverviewCard: View {
    let analysis: BudgetAnalysis
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("发薪周期 \(cycleTitle)").font(.subheadline.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
                Spacer()
                Image(systemName: alertIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(alertColor)
            }
            VStack(spacing: 8) {
                HStack {
                    Text("预算内已花").font(.caption).foregroundStyle(DesignSystem.textSecondary)
                    Spacer()
                    Text("\(analysis.totalSpent.formattedCurrency) / \(analysis.budgetLimit.formattedCurrency)")
                        .font(.caption.monospacedDigit()).foregroundStyle(DesignSystem.textSecondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6).fill(DesignSystem.dividerColor).frame(height: 12)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(progressGradient)
                            .frame(width: min(geo.size.width * CGFloat(min(analysis.usagePercent, 1.0)), geo.size.width), height: 12)
                            .animation(reduceMotion ? nil : DesignSystem.emphasisAnimation, value: analysis.usagePercent)
                    }
                }
                .frame(height: 12)
                HStack {
                    Text("\(Int(min(analysis.usagePercent, 9999) * 100))%").font(.caption2.monospacedDigit()).foregroundStyle(alertColor)
                    Spacer()
                    Text("预计周期末 \(analysis.projectedTotal.formattedCurrency)").font(.caption2.monospacedDigit()).foregroundStyle(DesignSystem.textTertiary)
                }

                if analysis.excludedSpent > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.caption2)
                        Text("已排除 \(analysis.excludedSpent.formattedCurrency)")
                            .font(.caption2.monospacedDigit())
                    }
                    .foregroundStyle(DesignSystem.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(spacing: 12) {
                budgetPill(title: "剩余预算", value: analysis.remainingBudget.formattedCurrency, color: analysis.remainingBudget >= 0 ? DesignSystem.incomeColor : DesignSystem.expenseColor)
                budgetPill(title: "今日可花", value: analysis.dailyAllowance.formattedCurrency, color: DesignSystem.primaryColor)
            }
        }
        .heroCard(accent: alertColor)
    }

    private func budgetPill(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(DesignSystem.textTertiary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(DesignSystem.softFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
    }

    private var cycleTitle: String {
        let endDisplay = Calendar.current.date(byAdding: .day, value: -1, to: analysis.periodEnd)?.shortDateString ?? analysis.periodEnd.shortDateString
        return "\(analysis.periodStart.shortDateString)-\(endDisplay)"
    }

    private var progressGradient: LinearGradient {
        switch analysis.alertLevel {
        case .healthy: return DesignSystem.incomeGradient
        case .warning: return DesignSystem.warningGradient
        case .danger: return DesignSystem.dangerGradient
        }
    }

    private var alertIcon: String {
        switch analysis.alertLevel {
        case .healthy: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .danger: return "exclamationmark.triangle.fill"
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
    let reminder: BudgetReminder

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: alertIcon).font(.title2).foregroundStyle(alertColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title).font(.subheadline.weight(.semibold)).foregroundStyle(DesignSystem.textPrimary)
                Text(reminder.message).font(.caption).foregroundStyle(DesignSystem.textSecondary)
            }
            Spacer()
        }
        .padding()
        .background(alertColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius).stroke(alertColor.opacity(0.3), lineWidth: 1))
    }

    private var alertIcon: String {
        reminder.iconName
    }

    private var alertColor: Color {
        switch reminder.alertLevel {
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
            metricCard(title: "日均消费", value: analysis.dailyAverage.formattedCurrency, icon: "chart.bar.fill", color: "#4E766A")
            metricCard(title: "今日可花", value: analysis.dailyAllowance.formattedCurrency, icon: "wallet.pass.fill",
                       color: analysis.alertLevel == .danger ? "#B86066" : "#4E766A")
            metricCard(title: "剩余预算", value: analysis.remainingBudget.formattedCurrency, icon: "banknote.fill",
                       color: analysis.remainingBudget >= 0 ? "#4E766A" : "#B86066")
            metricCard(title: "剩余天数", value: "\(analysis.daysRemaining) 天", icon: "calendar", color: "#4E766A")
            metricCard(title: "预计周期末", value: analysis.projectedTotal.formattedCurrency, icon: "chart.line.uptrend.xyaxis", color: "#4E766A")
            metricCard(
                title: analysis.projectedBalance >= 0 ? "预计结余" : "预计超支",
                value: analysis.projectedBalance.formattedCurrency,
                icon: analysis.projectedBalance >= 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                color: analysis.projectedBalance >= 0 ? "#4E766A" : "#B86066"
            )
            if analysis.excludedSpent > 0 {
                metricCard(title: "预算外支出", value: analysis.excludedSpent.formattedCurrency, icon: "line.3.horizontal.decrease.circle.fill", color: "#89928E")
            }
        }
    }

    private func metricCard(title: String, value: String, icon: String, color: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Image(systemName: icon).font(.caption).foregroundStyle(Color(hex: color)); Spacer() }
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(DesignSystem.textPrimary)
            Text(title).font(.caption).foregroundStyle(DesignSystem.textSecondary)
        }
        .glassCard()
    }
}

/// 添加预算
struct AddBudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let ledger: Ledger?
    let existingBudget: Budget?
    let payday: Int

    @State private var amountText = ""
    @State private var saveError: String?
    @State private var didLoadInitialAmount = false

    private var trimmedAmountText: String {
        amountText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        guard let amount = Decimal(string: trimmedAmountText) else { return false }
        return amount > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text(cycleTitle).font(.subheadline).foregroundStyle(DesignSystem.textSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("¥").font(.title2).foregroundStyle(DesignSystem.textSecondary)
                            TextField("0", text: $amountText).keyboardType(.decimalPad)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .monospacedDigit().foregroundStyle(DesignSystem.textPrimary).multilineTextAlignment(.center)
                        }.padding(.vertical, 20)
                        Text("发薪周期日常预算上限").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                    }
                    HStack(spacing: 12) {
                        ForEach(["3000", "5000", "8000", "10000"], id: \.self) { amount in
                            Button { amountText = amount } label: {
                                Text("¥\(amount)").font(.caption.weight(.medium))
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(DesignSystem.softFill).foregroundStyle(DesignSystem.textSecondary).clipShape(Capsule())
                            }
                        }
                    }
                    Spacer()
                }.padding()
            }
            .navigationTitle(existingBudget == nil ? "发薪周期预算" : "调整预算").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() }.foregroundStyle(DesignSystem.textSecondary) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { saveBudget() }.disabled(!canSave).foregroundStyle(DesignSystem.primaryColor)
                }
            }
            .onAppear {
                loadInitialAmountIfNeeded()
            }
            .alert("保存失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private var cycle: PayCycle {
        PayCycleService.cycle(payday: payday)
    }

    private var cycleTitle: String {
        let endDisplay = Calendar.current.date(byAdding: .day, value: -1, to: cycle.end)?.shortDateString ?? cycle.end.shortDateString
        return "\(cycle.start.fullDateString) - \(endDisplay)"
    }

    private func loadInitialAmountIfNeeded() {
        guard !didLoadInitialAmount else { return }
        didLoadInitialAmount = true

        if let existingBudget {
            amountText = NSDecimalNumber(decimal: existingBudget.monthlyLimit).stringValue
        }
    }

    private func saveBudget() {
        guard let amount = Decimal(string: trimmedAmountText), amount > 0 else { return }
        let cycle = PayCycleService.cycle(payday: payday)
        let year = cycle.budgetYear
        let month = cycle.budgetMonth
        let descriptor = FetchDescriptor<Budget>(
            predicate: #Predicate<Budget> { budget in
                budget.year == year && budget.month == month && budget.categoryId == nil
            }
        )

        do {
            let matchingBudgets = try modelContext.fetch(descriptor)
                .filter { matchesLedger($0) }
                .sorted { $0.createdAt > $1.createdAt }
            let currentBudget = existingBudget ?? matchingBudgets.first

            if let currentBudget {
                currentBudget.monthlyLimit = amount
                currentBudget.year = year
                currentBudget.month = month
                currentBudget.ledger = ledger
                currentBudget.categoryId = nil
                removeDuplicateBudgets(except: currentBudget, from: matchingBudgets)
            } else {
                let budget = Budget(monthlyLimit: amount, year: year, month: month, ledger: ledger)
                modelContext.insert(budget)
            }

            try modelContext.save()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func matchesLedger(_ budget: Budget) -> Bool {
        if let ledger {
            return budget.ledger?.id == ledger.id
        } else {
            return budget.ledger == nil
        }
    }

    private func removeDuplicateBudgets(except currentBudget: Budget, from budgets: [Budget]) {
        for budget in budgets where budget.id != currentBudget.id {
            modelContext.delete(budget)
        }
    }
}
