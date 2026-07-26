import SwiftUI
import SwiftData

enum ReportNavigationAnchor: Hashable {
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

struct ReportObservationScope: Hashable {
    let start: Date
    let end: Date
}

/// 日报、周报、月报、年报和发薪周期报共用的实时与历史报表页面。
/// 内容区与卡片实现见 `ReportObservedContent.swift` 与 `Cards/`。
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
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("报表提醒")
                    .accessibilityIdentifier("report.reminders")
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
                    .frame(width: 44, height: 44)
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
                    .frame(width: 44, height: 44)
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
