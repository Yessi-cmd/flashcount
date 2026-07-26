import SwiftUI

// MARK: - 汇总类卡片：连续记账、资金概览、智能分析、预算、洞察

extension ReportObservedContent {
    /// 打卡网格按周一对齐，表头与之一一对应。
    static let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]

    func streakCard(data: ReportData) -> some View {
        let days = data.streakDays
        let loggedCount = data.loggingDays.filter(\.isLogged).count

        return VStack(alignment: .leading, spacing: 12) {
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

            if !data.loggingDays.isEmpty {
                // 一个数字看不出记账节奏；把最近 5 周铺开，断档一眼可见。
                // 网格按周一对齐，每列固定对应同一个星期几，所以表头是有意义的。
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                    spacing: 4
                ) {
                    ForEach(Self.weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.system(size: 9))
                            .foregroundStyle(DesignSystem.textTertiary)
                    }
                    ForEach(data.loggingDays) { day in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                day.isLogged
                                    ? DesignSystem.primaryColor.opacity(0.85)
                                    : DesignSystem.dividerColor.opacity(0.6)
                            )
                            .frame(height: 16)
                    }
                }
                // 逐格朗读毫无意义，合并成一句结论。
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("最近 \(data.loggingDays.count) 天里有 \(loggedCount) 天记了账")
                .accessibilityIdentifier("report.loggingHeatmap")

                Text("最近 \(data.loggingDays.count) 天 · 已记 \(loggedCount) 天")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.textTertiary)
            }
        }
        .padding()
        .background(DesignSystem.softFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius).stroke(DesignSystem.borderColor))
    }

    func summaryCard(data: ReportData) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.space16) {
            HStack {
                Text(target.isCurrent ? "\(data.period.currentTitle)资金概览" : "报告期资金概览")
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
                summaryItem(title: "支出", amount: data.totalExpense, color: DesignSystem.expenseColor, change: data.expenseChange, metric: .expense)
                summaryItem(title: "收入", amount: data.totalIncome, color: DesignSystem.incomeColor, change: data.incomeChange, metric: .income, masked: privacyLock.hidesSensitiveAmounts)
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

    private func summaryItem(
        title: String,
        amount: Decimal,
        color: Color,
        change: Double?,
        metric: ReportMetricKind,
        masked: Bool = false
    ) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(DesignSystem.textTertiary)
            Text(masked ? privacyLock.maskedText : amount.formattedCurrency)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            if let change, !masked {
                let presentation = ReportChangePresentation.make(change: change, metric: metric)
                HStack(spacing: 2) {
                    Image(systemName: changeIcon(presentation.direction))
                        .font(.caption2)
                    Text(presentation.text)
                        .font(.caption2.monospacedDigit())
                }
                .foregroundStyle(changeColor(presentation))
            }
        }
        .frame(maxWidth: .infinity)
    }

    func smartAnalysisCard(data: ReportData) -> some View {
        let analysis = data.smartAnalysis
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("智能分析", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.textSecondary)
                Spacer()
                Text(data.period.rawValue)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(DesignSystem.primaryColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DesignSystem.primaryColor.opacity(0.1))
                    .clipShape(Capsule())
            }

            HStack(alignment: .top, spacing: 8) {
                analysisMetric(
                    title: analysis.averageLabel,
                    value: analysis.averageExpense.formattedCurrency,
                    detail: analysis.averageDetail,
                    icon: "divide.circle.fill"
                )
                analysisMetric(
                    title: peakMetricTitle(data.period),
                    value: analysis.peakBucket?.label ?? "暂无",
                    detail: analysis.peakBucket.map {
                        "\($0.expense.formattedCurrency) · \(ReportPercentageFormatter.categoryShare(analysis.peakShare))"
                    } ?? "尚无支出",
                    icon: "waveform.path.ecg.rectangle.fill"
                )
                analysisMetric(
                    title: analysis.activeBucketLabel,
                    value: "\(analysis.activeBucketCount)",
                    detail: "共 \(data.timeBuckets.count) 个区间",
                    icon: "calendar.badge.checkmark"
                )
            }

            if let projectedExpense = analysis.projectedExpense, data.period != .daily {
                HStack(spacing: 8) {
                    Image(systemName: "scope")
                        .foregroundStyle(DesignSystem.primaryColor)
                    Text("按当前节奏，本期预计支出")
                        .foregroundStyle(DesignSystem.textSecondary)
                    Spacer()
                    Text(projectedExpense.formattedCurrency)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(DesignSystem.textPrimary)
                }
                .font(.caption)
                .padding(.top, 2)
            }
        }
        .glassCard()
        .accessibilityIdentifier("report.smartAnalysis")
    }

    private func analysisMetric(
        title: String,
        value: String,
        detail: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(DesignSystem.primaryColor)
            Text(title)
                .font(.caption2)
                .foregroundStyle(DesignSystem.textTertiary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(DesignSystem.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(DesignSystem.textTertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func budgetCard(_ snapshot: ReportBudgetSnapshotValue) -> some View {
        let formatter = ReportDateRangeFormatter()
        let range = ReportDateRange(start: snapshot.cycle.start, end: snapshot.cycle.end)
        let cycleTitle = formatter.reportRange(range, period: .monthly).title
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("发薪周期预算", systemImage: "wallet.pass.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.textSecondary)
                Spacer()
                if let analysis = snapshot.analysis {
                    Label(analysis.alertLevel.rawValue, systemImage: budgetStatusIcon(analysis.alertLevel))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(budgetStatusColor(analysis.alertLevel))
                }
            }
            Text(cycleTitle)
                .font(.caption)
                .foregroundStyle(DesignSystem.textTertiary)

            if let analysis = snapshot.analysis {
                HStack {
                    Text("截至报告期末已花")
                    Spacer()
                    Text("\(analysis.totalSpent.formattedCurrency) / \(analysis.budgetLimit.formattedCurrency)")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(DesignSystem.textSecondary)
                GeometryReader { proxy in
                    Capsule().fill(DesignSystem.dividerColor)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(budgetStatusColor(analysis.alertLevel))
                                .frame(width: proxy.size.width * min(max(analysis.usagePercent, 0), 1))
                        }
                }
                .frame(height: 8)
                HStack {
                    Text(ReportPercentageFormatter.categoryShare(analysis.usagePercent))
                    Spacer()
                    Text("剩余 \(analysis.remainingBudget.formattedCurrency)")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(DesignSystem.textSecondary)
            } else {
                Text("未设置该发薪周期预算")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textTertiary)
            }
        }
        .glassCard()
        .accessibilityIdentifier("report.budgetCard")
    }

    /// 收入构成。收入侧此前只有总额和结余率，没有任何结构信息。
    @ViewBuilder
    func incomeCompositionCard(data: ReportData) -> some View {
        if !data.incomeBreakdown.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("收入构成", systemImage: "arrow.down.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DesignSystem.textSecondary)
                    Spacer()
                    if !privacyLock.hidesSensitiveAmounts {
                        Text(data.totalIncome.formattedCurrency)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(DesignSystem.incomeColor)
                    }
                }

                if privacyLock.hidesSensitiveAmounts {
                    // 锁定时连分类名都不展示：「工资」「奖金」本身就是隐私信息。
                    Button {
                        privacyLock.requestReveal()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                            Text("验证后查看收入来源构成")
                            Spacer()
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DesignSystem.primaryColor)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .background(DesignSystem.softFill)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                    }
                    .buttonStyle(.plain)
                } else {
                    ForEach(data.incomeBreakdown.prefix(5)) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 10) {
                                Image(systemName: item.categoryIcon)
                                    .font(.caption)
                                    .foregroundStyle(Color(hex: item.categoryColor))
                                    .frame(width: 22)
                                Text(item.categoryName)
                                    .font(.subheadline)
                                    .foregroundStyle(DesignSystem.textPrimary)
                                Spacer()
                                Text(item.amount.formattedCurrency)
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(DesignSystem.incomeColor)
                                Text(ReportPercentageFormatter.categoryShare(item.percentage))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(DesignSystem.textTertiary)
                            }
                            GeometryReader { proxy in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(DesignSystem.incomeColor.opacity(0.3))
                                    .frame(width: proxy.size.width * min(max(item.percentage, 0), 1), height: 3)
                            }
                            .frame(height: 3)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .glassCard()
            .accessibilityIdentifier("report.incomeComposition")
        }
    }

    func insightsCard(data: ReportData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("智能洞察", systemImage: "brain.head.profile.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DesignSystem.textSecondary)
            if data.smartAnalysis.insights.isEmpty {
                Text("该报告期数据不足，暂未生成趋势洞察")
                    .font(.caption).foregroundStyle(DesignSystem.textTertiary)
            } else {
                ForEach(data.smartAnalysis.insights) { insight in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: insight.isSensitive && privacyLock.hidesSensitiveAmounts ? "lock.fill" : insight.systemImage)
                            .font(.caption)
                            .foregroundStyle(insightColor(insight.tone))
                            .frame(width: 22, height: 22)
                            .background(insightColor(insight.tone).opacity(0.12))
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(insight.isSensitive && privacyLock.hidesSensitiveAmounts ? "收入洞察已隐藏" : insight.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DesignSystem.textPrimary)
                            Text(insight.isSensitive && privacyLock.hidesSensitiveAmounts ? "验证后显示结余率分析" : insight.detail)
                                .font(.caption)
                                .foregroundStyle(DesignSystem.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .glassCard()
        .accessibilityIdentifier("report.insights")
    }

    // MARK: - 小工具

    private func peakMetricTitle(_ period: ReportPeriod) -> String {
        switch period.bucketGranularity {
        case .hour: return "峰值时段"
        case .day: return "峰值日期"
        case .week: return "峰值周"
        case .month: return "峰值月"
        }
    }

    private func insightColor(_ tone: ReportInsightTone) -> Color {
        switch tone {
        case .positive: return DesignSystem.incomeColor
        case .neutral: return DesignSystem.primaryColor
        case .attention: return DesignSystem.warningColor
        }
    }

    private func changeIcon(_ direction: ReportChangeDirection) -> String {
        switch direction {
        case .increase: return "arrow.up.right"
        case .decrease: return "arrow.down.right"
        case .unchanged: return "minus"
        }
    }

    private func changeColor(_ presentation: ReportChangePresentation) -> Color {
        if presentation.isFavorable == true {
            DesignSystem.incomeColor
        } else if presentation.isFavorable == false {
            DesignSystem.expenseColor
        } else {
            DesignSystem.textTertiary
        }
    }

    func budgetStatusColor(_ level: BudgetAlertLevel) -> Color {
        switch level {
        case .healthy: return DesignSystem.incomeColor
        case .warning: return DesignSystem.warningColor
        case .danger: return DesignSystem.dangerColor
        }
    }

    func budgetStatusIcon(_ level: BudgetAlertLevel) -> String {
        switch level {
        case .healthy: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .danger: return "exclamationmark.triangle.fill"
        }
    }
}
