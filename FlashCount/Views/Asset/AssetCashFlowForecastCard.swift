import SwiftUI

/// 资产页上的 30 天现金流摘要；完整交互留在详情页。
struct AssetCashFlowForecastCard: View {
    let forecast: CashFlowForecast
    let hidesMoney: Bool
    let maskedText: String

    var body: some View {
        NavigationLink {
            CashFlowForecastView()
        } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("未来 30 天", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignSystem.textTertiary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("期末可能余额")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textTertiary)

                    if forecast.hasBalanceRange {
                        Text(
                            "\(displayAmount(forecast.endingBalanceLowerBound)) – \(displayAmount(forecast.endingBalanceUpperBound))"
                        )
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(
                            forecast.endingBalanceLowerBound >= 0
                                ? DesignSystem.textPrimary
                                : DesignSystem.expenseColor
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                        Text("典型 \(displayAmount(forecast.endingBalance))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(DesignSystem.textSecondary)
                    } else {
                        Text(displayAmount(forecast.endingBalance))
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(
                                forecast.endingBalance >= 0
                                    ? DesignSystem.textPrimary
                                    : DesignSystem.expenseColor
                            )
                    }
                }
                .privacySensitive(hidesMoney)

                Label(statusText, systemImage: statusIcon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor)
            }
            .glassCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("assets.cashFlowForecast")
    }

    private var riskPoint: CashFlowForecastPoint? {
        forecast.firstNegativePoint(for: .higherSpending)
    }

    private var statusText: String {
        if let point = forecast.firstNegativePoint(for: .lighterSpending) {
            return "\(point.date.shortDateString) 起，即使支出偏低也可能不足"
        }
        if let point = forecast.firstNegativePoint(for: .typical) {
            return "\(point.date.shortDateString) 起，典型节奏下可能不足"
        }
        if let point = riskPoint {
            return "\(point.date.shortDateString) 起，支出偏高时可能不足"
        }
        if let profile = forecast.routineProfile {
            switch profile.dataBasis {
            case .preliminary:
                return "记录周较少，暂显示初步趋势"
            case .limited:
                return "基于 \(profile.observedWeekCount) 个完整记录周"
            case .sufficient:
                return "基于最近 \(profile.observedWeekCount) 个完整记录周"
            case .unavailable:
                break
            }
        }
        return "继续记账后会形成历史常见区间"
    }

    private var statusIcon: String {
        riskPoint == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var statusColor: Color {
        guard riskPoint != nil else { return DesignSystem.incomeColor }
        return forecast.firstNegativePoint(for: .typical) == nil
            ? DesignSystem.warningColor
            : DesignSystem.dangerColor
    }

    private func displayAmount(_ amount: Decimal) -> String {
        hidesMoney ? maskedText : amount.formattedCurrency
    }
}
