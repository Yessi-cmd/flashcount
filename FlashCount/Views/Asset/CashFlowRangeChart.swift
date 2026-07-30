import Charts
import SwiftUI

struct CashFlowRangeChart: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var privacyLock: PrivacyLockService
    @State private var selectedDate: Date?

    let forecast: CashFlowForecast

    private var hidesMoney: Bool {
        PrivacyVisibilityPolicy.hidesAssets(isUnlocked: privacyLock.isUnlocked)
    }

    private var selectedPoint: CashFlowForecastPoint? {
        guard let selectedDate else { return nil }
        return forecast.points.min {
            abs($0.date.timeIntervalSince(selectedDate))
                < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("未来余额走势")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.textPrimary)
                    Text(chartSubtitle)
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textTertiary)
                }
                Spacer()
                if forecast.hasBalanceRange {
                    Label("常见范围", systemImage: "rectangle.inset.filled")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(DesignSystem.primaryColor)
                }
            }

            if hidesMoney {
                lockedChart
            } else if forecast.points.isEmpty {
                ContentUnavailableView(
                    "暂无可预测日期",
                    systemImage: "calendar.badge.exclamationmark"
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                if let selectedPoint {
                    selectedPointCallout(selectedPoint)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                chart
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.18),
                        value: selectedPoint?.date
                    )
            }
        }
        .glassCard()
        .accessibilityIdentifier("cashFlow.chart.card")
        .onAppear {
            if selectedDate == nil {
                selectedDate = forecast.points.last?.date
            }
        }
        .onChange(of: forecast.endDate) {
            selectedDate = forecast.points.last?.date
        }
    }

    private var lockedChart: some View {
        Button {
            privacyLock.requestReveal()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.title2)
                    .foregroundStyle(DesignSystem.primaryColor)
                Text("解锁后查看余额区间")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
                Text("坐标轴和走势也会隐藏，避免从图形推断金额")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 210)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("解锁并查看现金流走势图")
        .accessibilityIdentifier("cashFlow.chart.locked")
    }

    private var chart: some View {
        Chart {
            ForEach(forecast.points) { point in
                if forecast.hasBalanceRange {
                    AreaMark(
                        x: .value("日期", point.date),
                        yStart: .value("较高支出余额", chartValue(point.lowerBalance)),
                        yEnd: .value("较低支出余额", chartValue(point.upperBalance))
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [
                                DesignSystem.primaryColor.opacity(0.08),
                                DesignSystem.primaryColor.opacity(0.24)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .interpolationMethod(.monotone)
                }

                LineMark(
                    x: .value("日期", point.date),
                    y: .value("典型余额", chartValue(point.typicalBalance))
                )
                .foregroundStyle(DesignSystem.primaryColor)
                .lineStyle(.init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
                .accessibilityLabel(point.date.shortDateString)
                .accessibilityValue(point.typicalBalance.formattedCurrency)
            }

            RuleMark(y: .value("零余额", 0))
                .foregroundStyle(DesignSystem.dangerColor.opacity(0.55))
                .lineStyle(.init(lineWidth: 1, dash: [4, 4]))

            if let selectedPoint {
                RuleMark(x: .value("所选日期", selectedPoint.date))
                    .foregroundStyle(DesignSystem.textSecondary.opacity(0.45))
                    .lineStyle(.init(lineWidth: 1, dash: [3, 3]))

                PointMark(
                    x: .value("所选日期", selectedPoint.date),
                    y: .value("典型余额", chartValue(selectedPoint.typicalBalance))
                )
                .foregroundStyle(DesignSystem.primaryColor)
                .symbolSize(55)
            }
        }
        .chartYScale(domain: chartDomain)
        .chartXScale(
            range: .plotDimension(startPadding: 14, endPadding: 30)
        )
        .chartXAxis {
            AxisMarks(
                values: .stride(
                    by: .day,
                    count: max(forecast.points.count / 4, 1)
                )
            ) {
                AxisGridLine()
                    .foregroundStyle(DesignSystem.dividerColor.opacity(0.6))
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                    .foregroundStyle(DesignSystem.dividerColor.opacity(0.6))
                AxisValueLabel {
                    if let value = value.as(Double.self) {
                        Text(Decimal(value).formattedCompactAmount)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(DesignSystem.textTertiary)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let frame = geometry[plotFrame]
                                let x = value.location.x - frame.origin.x
                                guard x >= 0, x <= frame.width else { return }
                                selectedDate = proxy.value(atX: x)
                            }
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("选择预测日期")
                    .accessibilityHint("在图表上拖动，查看对应日期的余额范围")
                    .accessibilityIdentifier("cashFlow.chart.interaction")
            }
        }
        .sensoryFeedback(.selection, trigger: selectedPoint?.date)
        .frame(height: 230)
        .accessibilityLabel("未来余额走势，可拖动选择日期")
    }

    private func selectedPointCallout(
        _ point: CashFlowForecastPoint
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(point.date.shortDateString)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignSystem.textSecondary)
            if forecast.hasBalanceRange {
                Text(
                    "\(point.lowerBalance.formattedCurrency) – \(point.upperBalance.formattedCurrency)"
                )
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(
                    point.lowerBalance >= 0
                        ? DesignSystem.textPrimary
                        : DesignSystem.expenseColor
                )
                Text("典型 \(point.typicalBalance.formattedCurrency)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DesignSystem.textTertiary)
            } else {
                Text(point.typicalBalance.formattedCurrency)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(
                        point.typicalBalance >= 0
                            ? DesignSystem.textPrimary
                            : DesignSystem.expenseColor
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(DesignSystem.primaryColor.opacity(0.08))
        .clipShape(.rect(cornerRadius: 10))
        .accessibilityIdentifier("cashFlow.chart.selection")
    }

    private var chartSubtitle: String {
        if forecast.hasBalanceRange {
            return "色带是历史常见节奏，实线是典型余额"
        }
        if forecast.mode == .fixedAndRoutine,
           forecast.routineProfile?.dataBasis == .preliminary {
            return "记录周较少，暂显示一条初步趋势"
        }
        return "实线包含当前口径下的余额变化"
    }

    private var chartDomain: ClosedRange<Double> {
        var values: [Double] = [0]
        for point in forecast.points {
            values.append(chartValue(point.lowerBalance))
            values.append(chartValue(point.typicalBalance))
            values.append(chartValue(point.upperBalance))
        }
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        if minimum == maximum {
            return (minimum - 1)...(maximum + 1)
        }
        let padding = max((maximum - minimum) * 0.12, 1)
        return (minimum - padding)...(maximum + padding)
    }

    private func chartValue(_ amount: Decimal) -> Double {
        NSDecimalNumber(decimal: amount).doubleValue
    }
}
