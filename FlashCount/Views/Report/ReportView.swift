import SwiftUI
import SwiftData
import Charts

/// 周报 / 月报页面
struct ReportView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var privacyLock: PrivacyLockService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPeriod: ReportPeriod = .weekly
    @State private var reportData: ReportData?
    @State private var reportError: String?
    @Query private var recentTransactions: [Transaction]

    init() {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: Date())) ?? .distantPast
        _recentTransactions = Query(
            filter: #Predicate<Transaction> { $0.date >= cutoff },
            sort: \Transaction.date,
            order: .reverse
        )
    }

    /// 用于触发报表刷新。保持值类型摘要，避免为全部交易分配大型拼接字符串。
    private var transactionDigest: Int {
        var hasher = Hasher()
        for transaction in recentTransactions {
            hasher.combine(transaction.id)
            hasher.combine(transaction.amount)
            hasher.combine(transaction.isExpense)
            hasher.combine(transaction.date)
            hasher.combine(transaction.category?.id)
        }
        return hasher.finalize()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(accent: DesignSystem.primaryColor)

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
            .onChange(of: privacyLock.isUnlocked) { generateReport() }
            .onChange(of: transactionDigest) { generateReport() }
            .alert("报表读取失败", isPresented: Binding(
                get: { reportError != nil },
                set: { if !$0 { reportError = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(reportError ?? "")
            }
        }
    }

    // MARK: - 生成报表

    private func generateReport() {
        let service = ReportService(modelContext: modelContext)
        do {
            // 始终计算完整值，再由统一隐私状态负责遮罩，避免锁定时普通收入与工资口径不一致。
            let data = try service.generateReport(period: selectedPeriod, includePrivateIncome: true)
            withAnimation(reduceMotion ? nil : DesignSystem.standardAnimation) {
                reportData = data
            }
        } catch {
            reportError = error.localizedDescription
        }
    }

    // MARK: - 周期选择器

    private var periodPicker: some View {
        HStack(spacing: 0) {
            ForEach(ReportPeriod.allCases, id: \.self) { period in
                Button {
                    withAnimation(reduceMotion ? nil : DesignSystem.standardAnimation) { selectedPeriod = period }
                } label: {
                    Text(period.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedPeriod == period ? DesignSystem.primaryColor.opacity(0.2) : .clear)
                        .foregroundStyle(selectedPeriod == period ? DesignSystem.primaryColor : DesignSystem.textSecondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius).stroke(DesignSystem.borderColor))
    }

    // MARK: - 打卡连续天数

    private func streakCard(days: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 30))
                .foregroundStyle(DesignSystem.primaryColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("连续记账 \(days) 天")
                    .font(.headline)
                    .foregroundStyle(DesignSystem.textPrimary)
                Text(days >= 30 ? "稳定的记录习惯已经形成" : days >= 7 ? "保持这个节奏" : "每天记一笔，趋势会更清楚")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textSecondary)
            }
            Spacer()
        }
        .padding()
        .background(DesignSystem.softFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius).stroke(DesignSystem.borderColor))
    }

    // MARK: - 概览卡片

    private func summaryCard(data: ReportData) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.space16) {
            HStack {
                Text(data.period == .weekly ? "本周资金概览" : "本月资金概览")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.textSecondary)
                Spacer()
                Label(
                    privacyLock.hidesSensitiveAmounts ? "收入已隐藏" : (data.netChange >= 0 ? "有结余" : "需关注"),
                    systemImage: privacyLock.hidesSensitiveAmounts ? "lock.fill" : (data.netChange >= 0 ? "arrow.up.right" : "exclamationmark.triangle.fill")
                )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(privacyLock.hidesSensitiveAmounts ? DesignSystem.textTertiary : (data.netChange >= 0 ? DesignSystem.incomeColor : DesignSystem.expenseColor))
            }

            HStack(spacing: 0) {
                summaryItem(title: "支出", amount: data.totalExpense, color: DesignSystem.expenseColor, change: data.expenseChange)
                summaryItem(title: "收入", amount: data.totalIncome, color: DesignSystem.incomeColor, change: data.incomeChange, masked: privacyLock.hidesSensitiveAmounts)
                VStack(spacing: 4) {
                    Text("结余").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                    Text(privacyLock.hidesSensitiveAmounts ? privacyLock.maskedText : data.netChange.formattedCurrency)
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(privacyLock.hidesSensitiveAmounts ? DesignSystem.textTertiary : (data.netChange >= 0 ? DesignSystem.incomeColor : DesignSystem.expenseColor))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .heroCard(accent: privacyLock.hidesSensitiveAmounts ? DesignSystem.primaryColor : (data.netChange >= 0 ? DesignSystem.incomeColor : DesignSystem.expenseColor))
        .overlay(alignment: .bottom) {
            if privacyLock.hidesSensitiveAmounts {
                Button {
                    privacyLock.requestReveal()
                } label: {
                    Label("验证并显示全部收入", systemImage: "lock.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(DesignSystem.primaryColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(DesignSystem.cardBackground)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(DesignSystem.borderColor, lineWidth: 1))
                }
                .offset(y: 14)
            }
        }
    }

    private func summaryItem(title: String, amount: Decimal, color: Color, change: Double?, masked: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(DesignSystem.textTertiary)
            Text(masked ? privacyLock.maskedText : amount.formattedCurrency)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            if let change, !masked {
                let pct = Int(min(abs(change), 99.99) * 100)
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
            Text("每日消费").font(.subheadline.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)

            Chart {
                ForEach(Array(data.dailyExpenses.enumerated()), id: \.offset) { index, item in
                    BarMark(
                        x: .value("日期", item.0),
                        y: .value("金额", NSDecimalNumber(decimal: item.1).doubleValue)
                    )
                    .foregroundStyle(DesignSystem.primaryColor)
                    .cornerRadius(4)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            let absV = abs(v)
                            let label: String = if absV >= 100_000_000 {
                                String(format: "¥%.0f亿", v / 100_000_000)
                            } else if absV >= 10_000 {
                                String(format: "¥%.0f万", v / 10_000)
                            } else {
                                String(format: "¥%.0f", v)
                            }
                            Text(label).font(.caption2).foregroundStyle(DesignSystem.textTertiary)
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(DesignSystem.dividerColor)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    if let label = value.as(String.self), visibleLabels.contains(label) {
                        AxisValueLabel()
                            .font(.caption2)
                            .foregroundStyle(DesignSystem.textSecondary)
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
            Text("分类构成").font(.subheadline.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)

            if data.categoryBreakdown.isEmpty {
                Text("暂无支出数据").font(.caption).foregroundStyle(DesignSystem.textTertiary)
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
                            .foregroundStyle(DesignSystem.textPrimary)
                        Text("总支出").font(.caption2).foregroundStyle(DesignSystem.textSecondary)
                    }
                }

                // 图例
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 6) {
                    ForEach(data.categoryBreakdown.prefix(6)) { item in
                        HStack(spacing: 6) {
                            Circle().fill(Color(hex: item.categoryColor)).frame(width: 8, height: 8)
                            Text(item.categoryName).font(.caption2).foregroundStyle(DesignSystem.textSecondary)
                            Spacer()
                            Text("\(Int(min(item.percentage, 99.99) * 100))%").font(.caption2.monospacedDigit()).foregroundStyle(DesignSystem.textTertiary)
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
                Label("消费 Top 5", systemImage: "list.number")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.textSecondary)
                Spacer()
            }

            ForEach(Array(data.categoryBreakdown.prefix(5).enumerated()), id: \.offset) { index, item in
                HStack(spacing: 12) {
                    // 排名
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .frame(width: 20, height: 20)
                        .background(index < 3 ? Color.orange.opacity(0.2) : DesignSystem.softFill)
                        .foregroundStyle(index < 3 ? .orange : DesignSystem.textSecondary)
                        .clipShape(Circle())

                    // 图标
                    Image(systemName: item.categoryIcon)
                        .font(.caption)
                        .foregroundStyle(Color(hex: item.categoryColor))
                        .frame(width: 24)

                    // 名称
                    Text(item.categoryName)
                        .font(.subheadline)
                        .foregroundStyle(DesignSystem.textPrimary)

                    Spacer()

                    // 金额 + 占比
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(item.amount.formattedCurrency)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(DesignSystem.textPrimary)
                        Text("\(Int(min(item.percentage, 99.99) * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(DesignSystem.textTertiary)
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
            Text("🧠 消费洞察").font(.subheadline.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)

            if data.insights.isEmpty {
                Text("记账数据不足，多记几笔后生成洞察")
                    .font(.caption).foregroundStyle(DesignSystem.textTertiary)
            } else {
                ForEach(data.insights, id: \.self) { insight in
                    Text(insight)
                        .font(.subheadline)
                        .foregroundStyle(DesignSystem.textSecondary)
                        .padding(.vertical, 4)
                }
            }
        }
        .glassCard()
    }
}
