import Charts
import SwiftUI
import SwiftData

/// 展示未来现金余额变化。页面只读取本地快照，预测不会创建交易。
struct CashFlowForecastView: View {
    @EnvironmentObject private var privacyLock: PrivacyLockService
    @Query(sort: \CashPoolItem.sortOrder) private var cashPoolItems: [CashPoolItem]
    @Query(sort: \CashPoolState.updatedAt, order: .reverse) private var cashPoolStates: [CashPoolState]
    @Query(sort: \RecurringRule.nextDueDate) private var recurringRules: [RecurringRule]
    @Query private var occurrences: [RecurringOccurrence]
    @Query(sort: \InstallmentBill.createdAt, order: .reverse) private var installmentBills: [InstallmentBill]
    @Query private var recentTransactions: [Transaction]

    @AppStorage("payday") private var payday = 1
    @State private var horizon: CashFlowForecastHorizon = .thirtyDays
    @State private var mode: CashFlowForecastMode = .fixedAndRoutine

    init() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -120, to: Date.now) ?? .distantPast
        _recentTransactions = Query(
            filter: #Predicate<Transaction> { $0.date >= cutoff },
            sort: \Transaction.date,
            order: .reverse
        )
    }

    private var forecast: CashFlowForecast {
        CashFlowForecastService.forecast(
            cashPoolItems: cashPoolItems,
            cashPoolState: cashPoolStates.first,
            recurringRules: recurringRules,
            occurrences: occurrences,
            installmentBills: installmentBills,
            transactions: recentTransactions,
            horizon: horizon,
            mode: mode,
            payday: payday
        )
    }

    private var hidesMoney: Bool {
        PrivacyVisibilityPolicy.hidesAssets(isUnlocked: privacyLock.isUnlocked)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(accent: DesignSystem.primaryColor)

                ScrollView {
                    VStack(spacing: DesignSystem.sectionSpacing) {
                        controls
                        summaryCard
                        chartCard
                        eventList
                        explanationCard
                    }
                    .padding()
                }
            }
            .navigationTitle("现金流预测")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    PrivacyVisibilityButton()
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("预测范围", selection: $horizon) {
                ForEach(CashFlowForecastHorizon.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Picker("估算口径", selection: $mode) {
                ForEach(CashFlowForecastMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("预计期末余额", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
                Spacer()
                Text(horizon.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DesignSystem.textTertiary)
            }

            Text(displayAmount(forecast.endingBalance))
                .font(DesignSystem.Typography.amount)
                .monospacedDigit()
                .foregroundStyle(forecast.endingBalance >= 0 ? DesignSystem.textPrimary : DesignSystem.expenseColor)

            HStack(spacing: 0) {
                forecastMetric(title: "预计最低", amount: forecast.lowestPoint?.closingBalance ?? forecast.openingBalance)
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 34)
                forecastMetric(title: "固定收入", amount: forecast.confirmedIncome)
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 34)
                forecastMetric(title: "固定支出", amount: -forecast.confirmedExpense)
            }

            if let lowestPoint = forecast.lowestPoint, lowestPoint.closingBalance < 0 {
                Label(
                    "预计 \(lowestPoint.date.shortDateString) 起余额为负",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(DesignSystem.dangerColor)
            }
        }
        .glassCard()
    }

    private func forecastMetric(title: String, amount: Decimal) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(DesignSystem.textTertiary)
            Text(displayAmount(amount))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(amount >= 0 ? DesignSystem.incomeColor : DesignSystem.expenseColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("余额走势")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.textPrimary)

            if forecast.points.isEmpty {
                ContentUnavailableView("暂无可预测日期", systemImage: "calendar.badge.exclamationmark")
                    .frame(maxWidth: .infinity)
            } else {
                Chart(forecast.points) { point in
                    AreaMark(
                        x: .value("日期", point.date),
                        y: .value("余额", chartValue(point.closingBalance))
                    )
                    .foregroundStyle(DesignSystem.primaryColor.opacity(0.16))

                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("余额", chartValue(point.closingBalance))
                    )
                    .foregroundStyle(DesignSystem.primaryColor)
                    .lineStyle(.init(lineWidth: 2))
                }
                .chartYScale(domain: chartDomain)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(forecast.points.count / 4, 1))) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let value = value.as(Double.self) {
                                Text(shortChartAmount(value))
                            }
                        }
                    }
                }
                .frame(height: 220)
                .accessibilityLabel("未来余额走势")
            }
        }
        .glassCard()
    }

    private var eventList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("未来影响事项")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.textSecondary)
                Spacer()
                Text("\(forecast.events.count) 项")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textTertiary)
            }

            if forecast.events.isEmpty {
                ContentUnavailableView("暂无固定现金流", systemImage: "calendar.badge.plus")
                    .frame(maxWidth: .infinity)
                    .glassCard()
            } else {
                ForEach(forecast.events.prefix(12)) { event in
                    CashFlowEventRow(
                        event: event,
                        hidesMoney: hidesMoney,
                        maskedText: privacyLock.maskedText
                    )
                }
            }
        }
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("预测不写入账本", systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.textPrimary)
            Text("周期账单和分期是已配置事项；日常消费趋势是本机历史估算。发生真实交易后，预测会自动重新计算。")
                .font(.caption)
                .foregroundStyle(DesignSystem.textSecondary)
        }
        .glassCard()
    }

    private var chartDomain: ClosedRange<Double> {
        let values = forecast.points.map { chartValue($0.closingBalance) } + [0]
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        if minimum == maximum { return (minimum - 1)...(maximum + 1) }
        let padding = max((maximum - minimum) * 0.12, 1)
        return (minimum - padding)...(maximum + padding)
    }

    private func chartValue(_ amount: Decimal) -> Double {
        NSDecimalNumber(decimal: amount).doubleValue
    }

    private func displayAmount(_ amount: Decimal) -> String {
        hidesMoney ? privacyLock.maskedText : amount.formattedCurrency
    }

    private func shortChartAmount(_ amount: Double) -> String {
        Decimal(amount).formattedCompactAmount
    }
}

private struct CashFlowEventRow: View {
    let event: CashFlowEvent
    let hidesMoney: Bool
    let maskedText: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 30, height: 30)
                .background(iconColor.opacity(0.12))
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(event.isProtectedIncome ? "隐私收入" : event.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.textPrimary)
                Text("\(event.date.shortDateString) · \(event.source.title)")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textTertiary)
            }

            Spacer(minLength: 8)

            Text(hidesMoney || event.isProtectedIncome ? maskedText : event.signedAmount.formattedCurrency)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(event.signedAmount >= 0 ? DesignSystem.incomeColor : DesignSystem.expenseColor)
                .privacySensitive(hidesMoney || event.isProtectedIncome)
        }
        .padding(DesignSystem.cardPadding)
        .background(DesignSystem.cardBackground)
        .clipShape(.rect(cornerRadius: DesignSystem.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .stroke(DesignSystem.borderColor, lineWidth: 1)
        }
    }

    private var iconName: String {
        switch event.source {
        case .recurring: return "repeat.circle.fill"
        case .installment: return "creditcard.trianglebadge.exclamationmark.fill"
        case .routine: return "chart.line.uptrend.xyaxis"
        }
    }

    private var iconColor: Color {
        event.signedAmount >= 0 ? DesignSystem.incomeColor : DesignSystem.expenseColor
    }
}
