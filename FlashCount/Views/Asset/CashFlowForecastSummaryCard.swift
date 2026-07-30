import SwiftUI

struct CashFlowForecastSummaryCard: View {
    let forecast: CashFlowForecast
    let hidesMoney: Bool
    let maskedText: String

    private struct RiskMessage {
        let text: String
        let systemImage: String
        let color: Color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Label("预计期末余额", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
                Spacer()
                Text(forecast.horizon.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DesignSystem.textTertiary)
            }

            VStack(alignment: .leading, spacing: 5) {
                if forecast.hasBalanceRange {
                    Text(
                        "\(displayAmount(forecast.endingBalanceLowerBound)) – \(displayAmount(forecast.endingBalanceUpperBound))"
                    )
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(
                        forecast.endingBalanceLowerBound >= 0
                            ? DesignSystem.textPrimary
                            : DesignSystem.expenseColor
                    )
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                    .accessibilityIdentifier("cashFlow.summary.range")

                    Text("典型节奏 \(displayAmount(forecast.endingBalance))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DesignSystem.textSecondary)
                } else {
                    Text(displayAmount(forecast.endingBalance))
                        .font(DesignSystem.Typography.amount)
                        .monospacedDigit()
                        .foregroundStyle(
                            forecast.endingBalance >= 0
                                ? DesignSystem.textPrimary
                                : DesignSystem.expenseColor
                        )
                        .accessibilityIdentifier("cashFlow.summary.value")
                }

                Text(dataBasisText)
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textTertiary)
            }
            .privacySensitive(hidesMoney)

            AdaptiveMetricRow {
                metric(
                    title: "典型期末",
                    amount: forecast.endingBalance,
                    color: forecast.endingBalance >= 0
                        ? DesignSystem.primaryColor
                        : DesignSystem.expenseColor
                )
                AdaptiveMetricDivider(height: 34)
                metric(
                    title: "典型最低",
                    amount: forecast.lowestPoint?.typicalBalance ?? forecast.openingBalance,
                    color: (forecast.lowestPoint?.typicalBalance ?? forecast.openingBalance) >= 0
                        ? DesignSystem.warningColor
                        : DesignSystem.expenseColor
                )
                AdaptiveMetricDivider(height: 34)
                metric(
                    title: "已知净额",
                    amount: forecast.confirmedIncome - forecast.confirmedExpense,
                    color: forecast.confirmedIncome >= forecast.confirmedExpense
                        ? DesignSystem.incomeColor
                        : DesignSystem.expenseColor
                )
            }

            if let riskMessage {
                Label(riskMessage.text, systemImage: riskMessage.systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(riskMessage.color)
                    .accessibilityIdentifier("cashFlow.summary.risk")
            } else {
                Label("当前范围内未出现负余额", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DesignSystem.incomeColor)
            }
        }
        .glassCard()
    }

    @ViewBuilder
    private func metric(
        title: String,
        amount: Decimal,
        color: Color
    ) -> some View {
        AdaptiveMetric(
            title: title,
            value: displayAmount(amount),
            color: color
        )
        .privacySensitive(hidesMoney)
    }

    private var dataBasisText: String {
        guard forecast.mode == .fixedAndRoutine else {
            return "只计算已配置的周期账单与分期"
        }
        guard let profile = forecast.routineProfile else {
            return "缺少完整周记录，暂未估算日常支出"
        }

        switch profile.dataBasis {
        case .unavailable:
            return "缺少完整周记录，暂未估算日常支出"
        case .preliminary:
            return "基于 \(profile.observedWeekCount) 个完整记录周，先显示单一趋势"
        case .limited:
            return "基于 \(profile.observedWeekCount) 个完整记录周，范围仍会随记账完善"
        case .sufficient:
            return "基于最近 \(profile.observedWeekCount) 个完整记录周"
        }
    }

    private var riskMessage: RiskMessage? {
        if forecast.mode == .fixedOnly,
           let point = forecast.firstNegativePoint(for: .typical) {
            return RiskMessage(
                text: "仅算已知事项，\(point.date.shortDateString) 起余额可能为负",
                systemImage: "exclamationmark.triangle.fill",
                color: DesignSystem.dangerColor
            )
        }
        if let point = forecast.firstNegativePoint(for: .lighterSpending) {
            return RiskMessage(
                text: "即使按较低支出，\(point.date.shortDateString) 起也可能为负",
                systemImage: "exclamationmark.triangle.fill",
                color: DesignSystem.dangerColor
            )
        }
        if let point = forecast.firstNegativePoint(for: .typical) {
            return RiskMessage(
                text: "按典型节奏，\(point.date.shortDateString) 起可能为负",
                systemImage: "exclamationmark.triangle.fill",
                color: DesignSystem.dangerColor
            )
        }
        if let point = forecast.firstNegativePoint(for: .higherSpending) {
            return RiskMessage(
                text: "支出偏高时，\(point.date.shortDateString) 起可能为负",
                systemImage: "exclamationmark.circle.fill",
                color: DesignSystem.warningColor
            )
        }
        return nil
    }

    private func displayAmount(_ amount: Decimal) -> String {
        hidesMoney ? maskedText : amount.formattedCurrency
    }
}
