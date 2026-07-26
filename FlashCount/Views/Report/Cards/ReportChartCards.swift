import SwiftUI
import Charts

// MARK: - 图表类卡片：时间分布柱状图、分类构成环图、Top 5 排行

extension ReportObservedContent {
    func timeBucketBarChart(data: ReportData) -> some View {
        let selectedBucket = data.timeBuckets.first { $0.id == selectedBucketID }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(data.period.chartTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.textSecondary)
                Spacer()
                if let selectedBucket {
                    Text("\(selectedBucket.label) · \(selectedBucket.expense.formattedCurrency)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DesignSystem.textPrimary)
                }
            }

            if data.totalExpense == 0 {
                ContentUnavailableView("该报告期暂无支出", systemImage: "chart.bar.xaxis")
                    .frame(height: 180)
            } else {
                Chart(data.timeBuckets) { bucket in
                    BarMark(
                        x: .value("区间", bucket.range.start, unit: chartCalendarComponent(bucket.granularity)),
                        y: .value("金额", NSDecimalNumber(decimal: bucket.expense).doubleValue)
                    )
                    .foregroundStyle(selectedBucketID == nil || selectedBucketID == bucket.id
                        ? DesignSystem.primaryColor
                        : DesignSystem.primaryColor.opacity(0.35))
                    .cornerRadius(4)
                    .accessibilityLabel(bucket.label)
                    .accessibilityValue(bucket.expense.formattedCurrency)
                }
                .chartXSelection(value: $selectedBucketID)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let value = value.as(Double.self) {
                                Text(compactCurrency(value))
                                    .font(.caption2)
                                    .foregroundStyle(DesignSystem.textTertiary)
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(DesignSystem.dividerColor)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: axisValues(data.timeBuckets)) { value in
                        if let date = value.as(Date.self),
                           let bucket = data.timeBuckets.first(where: { $0.range.start == date }) {
                            AxisValueLabel(bucket.label)
                                .font(.caption2)
                                .foregroundStyle(DesignSystem.textSecondary)
                        }
                    }
                }
                .frame(height: 190)
                .accessibilityIdentifier("report.timeBucketChart")

                DisclosureGroup("查看图表明细", isExpanded: $showChartDetails) {
                    VStack(spacing: 8) {
                        ForEach(data.timeBuckets) { bucket in
                            HStack {
                                Text(bucket.label)
                                Spacer()
                                Text(bucket.expense.formattedCurrency).monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(DesignSystem.textSecondary)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.caption)
                .foregroundStyle(DesignSystem.textSecondary)
                .accessibilityIdentifier("report.chartDetails")
            }
        }
        .glassCard()
    }

    func categoryPieChart(data: ReportData) -> some View {
        let breakdown = displayedBreakdown(data.categoryBreakdown)
        return VStack(alignment: .leading, spacing: 12) {
            Text("分类构成").font(.subheadline.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)

            if breakdown.isEmpty {
                Text("暂无支出数据")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textTertiary)
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(breakdown) { item in
                    SectorMark(
                        angle: .value(item.categoryName, item.percentage),
                        innerRadius: .ratio(0.55),
                        angularInset: 2
                    )
                    .foregroundStyle(Color(hex: item.categoryColor))
                    .accessibilityLabel(item.categoryName)
                    .accessibilityValue("\(item.amount.formattedCurrency)，占 \(ReportPercentageFormatter.categoryShare(item.percentage))")
                }
                .frame(height: 180)
                .chartBackground { _ in
                    VStack {
                        Text(data.totalExpense.formattedCurrency)
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(DesignSystem.textPrimary)
                        Text("总支出").font(.caption2).foregroundStyle(DesignSystem.textSecondary)
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 6) {
                    ForEach(breakdown) { item in
                        HStack(spacing: 6) {
                            Circle().fill(Color(hex: item.categoryColor)).frame(width: 8, height: 8)
                            Text(item.categoryName).font(.caption2).foregroundStyle(DesignSystem.textSecondary)
                            Spacer()
                            Text(ReportPercentageFormatter.categoryShare(item.percentage))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(DesignSystem.textTertiary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .glassCard()
    }

    func topCategoriesCard(data: ReportData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("消费 Top 5", systemImage: "list.number")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DesignSystem.textSecondary)

            if data.categoryBreakdown.isEmpty {
                Text("暂无支出分类排行")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                ForEach(Array(data.categoryBreakdown.prefix(5).enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .frame(width: 20, height: 20)
                            .background(index < 3 ? Color.orange.opacity(0.2) : DesignSystem.softFill)
                            .foregroundStyle(index < 3 ? .orange : DesignSystem.textSecondary)
                            .clipShape(Circle())
                        Image(systemName: item.categoryIcon)
                            .font(.caption)
                            .foregroundStyle(Color(hex: item.categoryColor))
                            .frame(width: 24)
                        Text(item.categoryName).font(.subheadline).foregroundStyle(DesignSystem.textPrimary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(item.amount.formattedCurrency)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(DesignSystem.textPrimary)
                            Text(ReportPercentageFormatter.categoryShare(item.percentage))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(DesignSystem.textTertiary)
                        }
                    }
                    .accessibilityElement(children: .combine)

                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: item.categoryColor).opacity(0.3))
                            .frame(width: proxy.size.width * min(max(item.percentage, 0), 1), height: 3)
                    }
                    .frame(height: 3)
                }
            }
        }
        .glassCard()
    }

    // MARK: - 小工具

    private func displayedBreakdown(_ items: [CategorySpending]) -> [CategorySpending] {
        guard items.count > 6 else { return items }
        let visible = Array(items.prefix(5))
        let remainder = items.dropFirst(5)
        return visible + [CategorySpending(
            categoryName: "其他",
            categoryIcon: "ellipsis.circle.fill",
            categoryColor: "#89928E",
            amount: remainder.reduce(Decimal.zero) { $0 + $1.amount },
            percentage: remainder.reduce(0) { $0 + $1.percentage },
            changeFromLastPeriod: nil
        )]
    }

    private func axisValues(_ buckets: [ReportTimeBucket]) -> [Date] {
        let stride: Int
        switch buckets.first?.granularity {
        case .hour: stride = 4
        case .day: stride = buckets.count > 10 ? 5 : 1
        case .week: stride = 1
        case .month: stride = 2
        case nil: stride = 1
        }
        return buckets.enumerated().compactMap { index, bucket in
            index % stride == 0 || index == buckets.count - 1 ? bucket.range.start : nil
        }
    }

    private func chartCalendarComponent(_ granularity: ReportTimeBucket.Granularity) -> Calendar.Component {
        switch granularity {
        case .hour: return .hour
        case .day, .week: return .day
        case .month: return .month
        }
    }

    private func compactCurrency(_ value: Double) -> String {
        let absolute = abs(value)
        if absolute >= 100_000_000 { return String(format: "¥%.0f亿", value / 100_000_000) }
        if absolute >= 10_000 { return String(format: "¥%.0f万", value / 10_000) }
        return String(format: "¥%.0f", value)
    }
}
