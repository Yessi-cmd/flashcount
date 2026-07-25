import SwiftUI
import SwiftData
import Charts

private enum ReportNavigationAnchor: Hashable {
    case current
    case completed(Date)
    case scheduled(Date)

    var isCurrent: Bool {
        if case .current = self { return true }
        return false
    }

    func target(referenceDate: Date) -> ReportTarget {
        switch self {
        case .current: return .current(referenceDate: referenceDate)
        case .completed(let date): return .completed(containing: date)
        case .scheduled(let date): return .scheduled(triggerDate: date)
        }
    }
}

private struct ReportObservationScope: Hashable {
    let start: Date
    let end: Date
}

private struct ReportPageData {
    let report: ReportData
    let budget: ReportBudgetSnapshot
}

private enum ReportLoadState {
    case loading
    case refreshing(ReportPageData)
    case loaded(ReportPageData)
    case empty(ReportPageData)
    case failed(String)

    var visibleData: ReportPageData? {
        switch self {
        case .refreshing(let data), .loaded(let data), .empty(let data): return data
        case .loading, .failed: return nil
        }
    }
}

/// 日报、周报、月报、年报和发薪周期报共用的实时与历史报表页面。
struct ReportView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @AppStorage("payday") private var payday = 1
    @AppStorage(WeekendBudgetPreferences.storageKey) private var weekendBudgetMultiplierPercent = WeekendBudgetPreferences.defaultRawValue

    let isActive: Bool
    let requestedReport: ReportRoute.Request?
    let showsDismissButton: Bool

    @State private var selectedPeriod: ReportPeriod
    @State private var navigationAnchor: ReportNavigationAnchor
    @State private var referenceDate: Date
    @State private var appliedRequestID: UUID?
    @State private var showReminderSettings = false

    init(
        isActive: Bool = true,
        requestedReport: ReportRoute.Request? = nil,
        showsDismissButton: Bool = false
    ) {
        self.isActive = isActive
        self.requestedReport = requestedReport
        self.showsDismissButton = showsDismissButton

        let initialDate = requestedReport.map { request in
            switch request.target {
            case .current: return Date()
            case .scheduled(let deliveredAt): return deliveredAt
            }
        } ?? Date()
        let initialAnchor = requestedReport.map { request in
            switch request.target {
            case .current: return ReportNavigationAnchor.current
            case .scheduled(let deliveredAt): return ReportNavigationAnchor.scheduled(deliveredAt)
            }
        } ?? .current
        _selectedPeriod = State(initialValue: requestedReport?.period ?? .weekly)
        _navigationAnchor = State(initialValue: initialAnchor)
        _referenceDate = State(initialValue: initialDate)
        _appliedRequestID = State(initialValue: requestedReport?.id)
    }

    private var calculator: ReportPeriodCalculator {
        ReportPeriodCalculator(calendar: .current, payday: payday)
    }

    private var target: ReportTarget {
        navigationAnchor.target(referenceDate: referenceDate)
    }

    private var selection: ReportPeriodSelection {
        calculator.selection(for: selectedPeriod, target: target)
    }

    private var observationScope: ReportObservationScope {
        let selection = selection
        let budgetAnchor = target.isCurrent
            ? selection.reportRange.end
            : (Calendar.current.date(byAdding: .second, value: -1, to: selection.reportRange.end)
                ?? selection.reportRange.start)
        let cycle = PayCycleService.cycle(containing: budgetAnchor, payday: payday)
        let reportEnd = target.isCurrent
            ? calculator.currentPeriodEnd(for: selectedPeriod, referenceDate: referenceDate)
            : selection.reportRange.end
        return ReportObservationScope(
            start: min(selection.comparisonRange.start, cycle.start),
            end: max(reportEnd, target.isCurrent ? cycle.end : selection.reportRange.end)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(accent: DesignSystem.primaryColor)

                ScrollView {
                    VStack(spacing: DesignSystem.sectionSpacing) {
                        periodPicker
                        rangeNavigator

                        ReportObservedContent(
                            scope: observationScope,
                            period: selectedPeriod,
                            target: target,
                            payday: payday,
                            weekendBudgetMultiplierPercent: weekendBudgetMultiplierPercent
                        )
                        .id(observationScope)

#if DEBUG
                        Color.clear
                            .frame(height: 1)
                            .accessibilityElement()
                            .accessibilityLabel("报表内容结尾")
                            .accessibilityIdentifier("report.contentEnd")
#endif
                    }
                    .padding()
                }
                .accessibilityIdentifier("report.scroll")
            }
            .navigationTitle("报表")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if showsDismissButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("关闭") { dismiss() }
                            .accessibilityIdentifier("report.foreground.close")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showReminderSettings = true
                    } label: {
                        Image(systemName: "bell.badge")
                    }
                    .accessibilityLabel("报表提醒")
                }
            }
            .sheet(isPresented: $showReminderSettings) {
                ReportReminderSettingsView()
            }
            .onAppear {
                if requestedReport == nil {
                    referenceDate = Date()
                }
                applyRequestedReportIfNeeded(requestedReport)
            }
            .onChange(of: requestedReport) { _, request in
                applyRequestedReportIfNeeded(request)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                referenceDate = Date()
            }
            .onChange(of: isActive) { _, active in
                if active {
                    referenceDate = Date()
                    applyRequestedReportIfNeeded(requestedReport)
                }
            }
            .task(id: midnightTaskID) {
                guard midnightTaskID.shouldRun else { return }
                while !Task.isCancelled {
                    let now = Date()
                    let midnight = calculator.nextLocalMidnight(after: now)
                    let nanoseconds = UInt64(max(midnight.timeIntervalSince(now), 1) * 1_000_000_000)
                    do {
                        try await Task.sleep(nanoseconds: nanoseconds)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    referenceDate = Date()
                }
            }
        }
    }

    private var midnightTaskID: MidnightTaskID {
        MidnightTaskID(
            shouldRun: isActive && scenePhase == .active && navigationAnchor.isCurrent,
            period: selectedPeriod
        )
    }

    @ViewBuilder
    private var periodPicker: some View {
        if #available(iOS 26.0, *) {
            liquidGlassPeriodPicker
        } else {
            legacyPeriodPicker
        }
    }

    @available(iOS 26.0, *)
    private var liquidGlassPeriodPicker: some View {
        LiquidGlassContainer(spacing: 5) {
            HStack(spacing: 5) {
                ForEach(ReportPeriod.allCases, id: \.self) { period in
                    let isSelected = selectedPeriod == period
                    Button {
                        selectPeriod(period)
                    } label: {
                        Text(period.rawValue)
                            .font(.subheadline.weight(isSelected ? .semibold : .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(isSelected ? DesignSystem.primaryColor : DesignSystem.textSecondary)
                            .contentShape(Rectangle())
                            .liquidGlassSurface(
                                tint: isSelected ? DesignSystem.primaryColor.opacity(0.18) : nil,
                                shape: .roundedRectangle(12),
                                isInteractive: true,
                                isClear: !isSelected
                            )
                            .animation(reduceMotion ? nil : DesignSystem.glassSelectionAnimation, value: isSelected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("report.period.\(period.accessibilityKey)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private var legacyPeriodPicker: some View {
        HStack(spacing: 0) {
            ForEach(ReportPeriod.allCases, id: \.self) { period in
                Button {
                    selectPeriod(period)
                } label: {
                    Text(period.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedPeriod == period ? DesignSystem.primaryColor.opacity(0.2) : .clear)
                        .foregroundStyle(selectedPeriod == period ? DesignSystem.primaryColor : DesignSystem.textSecondary)
                }
                .accessibilityIdentifier("report.period.\(period.accessibilityKey)")
                .accessibilityAddTraits(selectedPeriod == period ? .isSelected : [])
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius).stroke(DesignSystem.borderColor))
    }

    @ViewBuilder
    private var rangeNavigator: some View {
        if #available(iOS 26.0, *) {
            liquidGlassRangeNavigator
        } else {
            legacyRangeNavigator
        }
    }

    @available(iOS 26.0, *)
    private var liquidGlassRangeNavigator: some View {
        let presentation = ReportDateRangeFormatter().reportRange(selection.reportRange, period: selectedPeriod)
        return LiquidGlassContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: showPreviousRange) {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .foregroundStyle(DesignSystem.primaryColor)
                        .liquidGlassSurface(shape: .circle, isInteractive: true, isClear: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("上一个\(selectedPeriod.rawValue)")
                .accessibilityIdentifier("report.previousPeriod")

                VStack(spacing: 3) {
                    Text(presentation.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.textPrimary)
                        .multilineTextAlignment(.center)
                        .contentTransition(.numericText())
                        .accessibilityLabel(presentation.accessibilityLabel)
                        .accessibilityIdentifier("report.range")
                    Text(rangeStatusTitle)
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 42)
                .padding(.horizontal, 10)
                .liquidGlassSurface(
                    tint: DesignSystem.primaryColor.opacity(0.06),
                    shape: .roundedRectangle(14),
                    isClear: true
                )
                .animation(reduceMotion ? nil : DesignSystem.standardAnimation, value: presentation.title)

                Button(action: showNextRange) {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .foregroundStyle(
                            navigationAnchor.isCurrent
                                ? DesignSystem.textTertiary
                                : DesignSystem.primaryColor
                        )
                        .liquidGlassSurface(
                            shape: .circle,
                            isInteractive: !navigationAnchor.isCurrent,
                            isClear: true
                        )
                }
                .buttonStyle(.plain)
                .disabled(navigationAnchor.isCurrent)
                .accessibilityLabel("下一个\(selectedPeriod.rawValue)")
                .accessibilityIdentifier("report.nextPeriod")
            }
        }
    }

    private var legacyRangeNavigator: some View {
        let presentation = ReportDateRangeFormatter().reportRange(selection.reportRange, period: selectedPeriod)
        return HStack(spacing: 12) {
            Button(action: showPreviousRange) {
                Image(systemName: "chevron.left")
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel("上一个\(selectedPeriod.rawValue)")
            .accessibilityIdentifier("report.previousPeriod")

            VStack(spacing: 3) {
                Text(presentation.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(presentation.accessibilityLabel)
                    .accessibilityIdentifier("report.range")
                Text(rangeStatusTitle)
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.textTertiary)
            }
            .frame(maxWidth: .infinity)

            Button(action: showNextRange) {
                Image(systemName: "chevron.right")
                    .frame(width: 34, height: 34)
            }
            .disabled(navigationAnchor.isCurrent)
            .accessibilityLabel("下一个\(selectedPeriod.rawValue)")
            .accessibilityIdentifier("report.nextPeriod")
        }
        .padding(.horizontal, 6)
    }

    private func selectPeriod(_ period: ReportPeriod) {
        withAnimation(reduceMotion ? nil : DesignSystem.standardAnimation) {
            selectedPeriod = period
            navigationAnchor = .current
            referenceDate = Date()
        }
    }

    private func showPreviousRange() {
        navigationAnchor = .completed(calculator.previousCompletedAnchor(for: selection))
    }

    private func showNextRange() {
        guard !navigationAnchor.isCurrent else { return }
        if let next = calculator.nextCompletedAnchor(for: selection, referenceDate: Date()) {
            navigationAnchor = .completed(next)
        } else {
            navigationAnchor = .current
            referenceDate = Date()
        }
    }

    private var rangeStatusTitle: String {
        switch navigationAnchor {
        case .current: return "当前进行中"
        case .completed: return "已完成报表"
        case .scheduled: return "提醒对应报表"
        }
    }

    private func applyRequestedReportIfNeeded(_ request: ReportRoute.Request?) {
        guard let request, appliedRequestID != request.id else { return }
        appliedRequestID = request.id
        selectedPeriod = request.period
        switch request.target {
        case .current:
            navigationAnchor = .current
            referenceDate = Date()
        case .scheduled(let deliveredAt):
            navigationAnchor = .scheduled(deliveredAt)
            referenceDate = deliveredAt
        }
    }
}

private struct MidnightTaskID: Hashable {
    let shouldRun: Bool
    let period: ReportPeriod
}

private struct ReportObservedContent: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var privacyLock: PrivacyLockService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var observedTransactions: [Transaction]
    @Query(sort: \Budget.createdAt) private var budgets: [Budget]

    let scope: ReportObservationScope
    let period: ReportPeriod
    let target: ReportTarget
    let payday: Int
    let weekendBudgetMultiplierPercent: Int

    @State private var state: ReportLoadState = .loading
    @State private var retryToken = 0
    @State private var selectedBucketID: Date?
    @State private var showChartDetails = false

    init(
        scope: ReportObservationScope,
        period: ReportPeriod,
        target: ReportTarget,
        payday: Int,
        weekendBudgetMultiplierPercent: Int
    ) {
        self.scope = scope
        self.period = period
        self.target = target
        self.payday = payday
        self.weekendBudgetMultiplierPercent = weekendBudgetMultiplierPercent
        let start = scope.start
        let end = scope.end
        _observedTransactions = Query(
            filter: #Predicate<Transaction> { transaction in
                transaction.date >= start && transaction.date < end
            },
            sort: \Transaction.date,
            order: .reverse
        )
    }

    private var weekendBudgetMultiplier: Decimal {
        WeekendBudgetPreferences.multiplier(for: weekendBudgetMultiplierPercent)
    }

    private var transactionDigest: Int {
        var hasher = Hasher()
        for transaction in observedTransactions {
            hasher.combine(transaction.id)
            hasher.combine(transaction.amount)
            hasher.combine(transaction.isExpense)
            hasher.combine(transaction.date)
            hasher.combine(transaction.dailyBudgetOverride)
            hasher.combine(transaction.category?.id)
            hasher.combine(transaction.category?.reportDisplayName)
            hasher.combine(transaction.category?.reportIcon)
            hasher.combine(transaction.category?.reportColorHex)
            hasher.combine(transaction.category?.dailyBudgetOverride)
        }
        for budget in budgets {
            hasher.combine(budget.id)
            hasher.combine(budget.monthlyLimit)
            hasher.combine(budget.year)
            hasher.combine(budget.month)
            hasher.combine(budget.categoryId)
            hasher.combine(budget.createdAt)
        }
        return hasher.finalize()
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView("正在生成报表…")
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .accessibilityIdentifier("report.loading")
            case .failed(let message):
                ContentUnavailableView {
                    Label("报表读取失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") { retryToken += 1 }
                        .accessibilityIdentifier("report.retry")
                }
            case .empty(let data):
                VStack(spacing: DesignSystem.sectionSpacing) {
                    ContentUnavailableView(
                        "该报告期暂无记录",
                        systemImage: "chart.bar.xaxis",
                        description: Text("记录一笔收支后，这里会生成趋势与消费洞察。")
                    )
                    .accessibilityIdentifier("report.empty")
                    budgetCard(data.budget)
                }
            case .refreshing(let data):
                reportContent(data)
                    .overlay(alignment: .topTrailing) { ProgressView().controlSize(.small) }
            case .loaded(let data):
                reportContent(data)
            }
        }
        .task(id: GenerationKey(
            digest: transactionDigest,
            retry: retryToken,
            weekendBudgetMultiplierPercent: weekendBudgetMultiplierPercent
        )) {
            generateReport()
        }
    }

    @ViewBuilder
    private func reportContent(_ page: ReportPageData) -> some View {
        let data = page.report
        VStack(spacing: DesignSystem.sectionSpacing) {
            streakCard(days: data.streakDays)
            summaryCard(data: data)
            smartAnalysisCard(data: data)
            budgetCard(page.budget)
            timeBucketBarChart(data: data)
            categoryPieChart(data: data)
            topCategoriesCard(data: data)
            insightsCard(data: data)
        }
    }

    private func smartAnalysisCard(data: ReportData) -> some View {
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
                .font(.system(size: 9))
                .foregroundStyle(DesignSystem.textTertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func generateReport() {
        let previous = state.visibleData
        state = previous.map(ReportLoadState.refreshing) ?? .loading
        do {
            let service = ReportService(modelContext: modelContext, payday: payday)
            let report = try service.generateReport(period: period, target: target, includePrivateIncome: true)
            let budget = ReportBudgetSnapshotService.snapshot(
                budgets: budgets,
                transactions: observedTransactions,
                reportRange: report.reportRange,
                target: target,
                payday: payday,
                weekendMultiplier: weekendBudgetMultiplier
            )
            let page = ReportPageData(report: report, budget: budget)
            withAnimation(reduceMotion ? nil : DesignSystem.standardAnimation) {
                state = report.transactionCount == 0 ? .empty(page) : .loaded(page)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

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

    private func summaryCard(data: ReportData) -> some View {
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
                        .font(.system(size: 8))
                    Text(presentation.text)
                        .font(.caption2.monospacedDigit())
                }
                .foregroundStyle(changeColor(presentation))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func timeBucketBarChart(data: ReportData) -> some View {
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

    private func categoryPieChart(data: ReportData) -> some View {
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

    private func topCategoriesCard(data: ReportData) -> some View {
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

    private func budgetCard(_ snapshot: ReportBudgetSnapshot) -> some View {
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

    private func insightsCard(data: ReportData) -> some View {
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

    private func budgetStatusColor(_ level: BudgetAlertLevel) -> Color {
        switch level {
        case .healthy: return DesignSystem.incomeColor
        case .warning: return DesignSystem.warningColor
        case .danger: return DesignSystem.dangerColor
        }
    }

    private func budgetStatusIcon(_ level: BudgetAlertLevel) -> String {
        switch level {
        case .healthy: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .danger: return "exclamationmark.triangle.fill"
        }
    }
}

private struct GenerationKey: Hashable {
    let digest: Int
    let retry: Int
    let weekendBudgetMultiplierPercent: Int
}
