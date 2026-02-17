import SwiftUI
import SwiftData
import Charts

/// 周报 / 月报页面
struct ReportView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedPeriod: ReportPeriod = .weekly
    @State private var reportData: ReportData?

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DesignSystem.sectionSpacing) {
                        // 周报/月报切换
                        periodPicker
                        
                        if let data = reportData {
                            // 记账打卡
                            streakCard(days: data.streakDays)
                            // 概览
                            summaryCard(data: data)
                            // 每日消费柱状图
                            dailyBarChart(data: data)
                            // 分类饼图
                            categoryPieChart(data: data)
                            // Top 5 排行
                            topCategoriesCard(data: data)
                            // 消费洞察
                            insightsCard(data: data)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("报表")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { generateReport() }
            .onChange(of: selectedPeriod) { generateReport() }
        }
    }

    // MARK: - 生成报表

    private func generateReport() {
        let service = ReportService(modelContext: modelContext)
        withAnimation(.easeInOut(duration: 0.3)) {
            reportData = service.generateReport(period: selectedPeriod)
        }
    }

    // MARK: - 周期选择器

    private var periodPicker: some View {
        HStack(spacing: 0) {
            ForEach(ReportPeriod.allCases, id: \.self) { period in
                Button {
                    withAnimation(.spring(response: 0.3)) { selectedPeriod = period }
                } label: {
                    Text(period.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedPeriod == period ? DesignSystem.primaryColor.opacity(0.2) : .clear)
                        .foregroundStyle(selectedPeriod == period ? DesignSystem.primaryColor : .white.opacity(0.5))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius).stroke(.white.opacity(0.1)))
    }

    // MARK: - 打卡连续天数

    private func streakCard(days: Int) -> some View {
        HStack(spacing: 12) {
            Text("🔥")
                .font(.system(size: 36))
            VStack(alignment: .leading, spacing: 2) {
                Text("连续记账 \(days) 天")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(days >= 30 ? "厉害了！坚持就是胜利 💪" : days >= 7 ? "保持住，养成习惯！" : "每天记一笔，积少成多 ✨")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding()
        .background(
            LinearGradient(colors: [.orange.opacity(0.15), .red.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius).stroke(.orange.opacity(0.2)))
    }

    // MARK: - 概览卡片

    private func summaryCard(data: ReportData) -> some View {
        HStack(spacing: 0) {
            summaryItem(title: "支出", amount: data.totalExpense, color: DesignSystem.expenseColor, change: data.expenseChange)
            summaryItem(title: "收入", amount: data.totalIncome, color: DesignSystem.incomeColor, change: data.incomeChange)
            VStack(spacing: 4) {
                Text("结余").font(.caption).foregroundStyle(.white.opacity(0.4))
                Text(data.netChange.formattedCurrency)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(data.netChange >= 0 ? DesignSystem.incomeColor : DesignSystem.expenseColor)
            }
            .frame(maxWidth: .infinity)
        }
        .glassCard()
    }

    private func summaryItem(title: String, amount: Decimal, color: Color, change: Double?) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.4))
            Text(amount.formattedCurrency)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            if let change {
                let pct = Int(abs(change) * 100)
                HStack(spacing: 2) {
                    Image(systemName: change > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 8))
                    Text("\(pct)%")
                        .font(.caption2.monospacedDigit())
                }
                .foregroundStyle(change > 0 ? DesignSystem.expenseColor : DesignSystem.incomeColor)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 每日消费柱状图

    private func dailyBarChart(data: ReportData) -> some View {
        let totalDays = data.dailyExpenses.count
        let labelStride = totalDays > 14 ? 5 : (totalDays > 7 ? 3 : 1)
        // 预计算需要显示标签的日期
        let visibleLabels: Set<String> = {
            var s = Set<String>()
            for (i, item) in data.dailyExpenses.enumerated() {
                if i % labelStride == 0 || i == totalDays - 1 {
                    s.insert(item.0)
                }
            }
            return s
        }()

        return VStack(alignment: .leading, spacing: 12) {
            Text("每日消费").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.7))

            Chart {
                ForEach(Array(data.dailyExpenses.enumerated()), id: \.offset) { index, item in
                    BarMark(
                        x: .value("日期", item.0),
                        y: .value("金额", NSDecimalNumber(decimal: item.1).doubleValue)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [DesignSystem.primaryColor, DesignSystem.primaryColor.opacity(0.5)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .cornerRadius(4)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("¥\(Int(v))").font(.caption2).foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(.white.opacity(0.08))
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    if let label = value.as(String.self), visibleLabels.contains(label) {
                        AxisValueLabel()
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .frame(height: 180)
        }
        .glassCard()
    }

    // MARK: - 分类饼图

    private func categoryPieChart(data: ReportData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分类构成").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.7))

            if data.categoryBreakdown.isEmpty {
                Text("暂无支出数据").font(.caption).foregroundStyle(.white.opacity(0.3))
                    .frame(height: 160).frame(maxWidth: .infinity)
            } else {
                Chart(data.categoryBreakdown) { item in
                    SectorMark(
                        angle: .value(item.categoryName, item.percentage),
                        innerRadius: .ratio(0.55),
                        angularInset: 2
                    )
                    .foregroundStyle(Color(hex: item.categoryColor))
                }
                .frame(height: 180)
                .chartBackground { _ in
                    VStack {
                        Text(data.totalExpense.formattedCurrency)
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                        Text("总支出").font(.caption2).foregroundStyle(.white.opacity(0.5))
                    }
                }

                // 图例
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 6) {
                    ForEach(data.categoryBreakdown.prefix(6)) { item in
                        HStack(spacing: 6) {
                            Circle().fill(Color(hex: item.categoryColor)).frame(width: 8, height: 8)
                            Text(item.categoryName).font(.caption2).foregroundStyle(.white.opacity(0.7))
                            Spacer()
                            Text("\(Int(item.percentage * 100))%").font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
            }
        }
        .glassCard()
    }

    // MARK: - Top 5 排行

    private func topCategoriesCard(data: ReportData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🏆 消费 Top 5").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.7))
                Spacer()
            }

            ForEach(Array(data.categoryBreakdown.prefix(5).enumerated()), id: \.offset) { index, item in
                HStack(spacing: 12) {
                    // 排名
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .frame(width: 20, height: 20)
                        .background(index < 3 ? Color.orange.opacity(0.2) : .white.opacity(0.06))
                        .foregroundStyle(index < 3 ? .orange : .white.opacity(0.5))
                        .clipShape(Circle())

                    // 图标
                    Image(systemName: item.categoryIcon)
                        .font(.caption)
                        .foregroundStyle(Color(hex: item.categoryColor))
                        .frame(width: 24)

                    // 名称
                    Text(item.categoryName)
                        .font(.subheadline)
                        .foregroundStyle(.white)

                    Spacer()

                    // 金额 + 占比
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(item.amount.formattedCurrency)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                        Text("\(Int(item.percentage * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                // 进度条
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: item.categoryColor).opacity(0.3))
                        .frame(width: geo.size.width * item.percentage, height: 3)
                }
                .frame(height: 3)
            }
        }
        .glassCard()
    }

    // MARK: - 消费洞察

    private func insightsCard(data: ReportData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🧠 消费洞察").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.7))

            if data.insights.isEmpty {
                Text("记账数据不足，多记几笔生成洞察 ✨")
                    .font(.caption).foregroundStyle(.white.opacity(0.4))
            } else {
                ForEach(data.insights, id: \.self) { insight in
                    Text(insight)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.vertical, 4)
                }
            }
        }
        .glassCard()
    }
}
