import SwiftUI
import SwiftData

private enum MainSheetDestination: Identifiable, Equatable {
    case quickEntry
    case deliveredReport(ReportRoute.Request)

    var id: String {
        switch self {
        case .quickEntry: return "quickEntry"
        case .deliveredReport(let request): return "deliveredReport.\(request.id.uuidString)"
        }
    }
}

/// 主标签栏视图
struct MainTabView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var privacyLock: PrivacyLockService
    @EnvironmentObject private var quickEntryFeedback: QuickEntryFeedbackCenter
    @State private var selectedTab: Int
    @State private var animatedSelectedTab: Int
    @State private var presentedSheet: MainSheetDestination?
    @State private var pendingForegroundReport: ReportRoute.Request?
    @State private var tabReportRequest: ReportRoute.Request?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(QuickEntryRoute.requestKey) private var shouldShowQuickEntry = false
    @AppStorage(ReportRoute.requestKey) private var shouldShowReport = false
    @State private var showOnboarding = false

    init() {
        var initialTab = 0
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let marker = arguments.firstIndex(of: "-visualReviewTab"),
           arguments.indices.contains(marker + 1),
           let requestedTab = Int(arguments[marker + 1]),
           [0, 1, 3, 4].contains(requestedTab) {
            initialTab = requestedTab
        }
#endif
        _selectedTab = State(initialValue: initialTab)
        _animatedSelectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                LedgerView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(0)
                BudgetView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(1)
                Color.clear // 中间占位 (记账按钮)
                    .toolbar(.hidden, for: .tabBar)
                    .tag(2)
                ReportView(
                    isActive: selectedTab == 3,
                    requestedReport: tabReportRequest
                )
                    .toolbar(.hidden, for: .tabBar)
                    .tag(3)
                AssetDashboardView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(4)
            }
            .tint(DesignSystem.primaryColor)
            .toolbar(.hidden, for: .tabBar)
            // 记完一笔的确认与撤销浮在页面之上：不改变布局，也不挡住底栏。
            .overlay(alignment: .bottom) {
                if let entry = quickEntryFeedback.lastSaved {
                    QuickEntrySavedToast(entry: entry)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86),
                value: quickEntryFeedback.lastSaved?.id
            )

            // 与页面并列布局，从结构上杜绝所有 Tab 内容进入底栏区域。
            customTabBar
        }
        .background(DesignSystem.surfaceBackground)
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .quickEntry:
                QuickEntryView()
            case .deliveredReport(let request):
                ReportView(
                    requestedReport: request,
                    showsDismissButton: true
                )
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding) {
                hasCompletedOnboarding = true
            }
        }
        .onAppear {
            if !hasCompletedOnboarding {
                showOnboarding = true
            }
            processQuickEntryRequestIfNeeded()
            processReportRequestIfNeeded()
            prepareForegroundReportUITestIfNeeded()
        }
        .onChange(of: shouldShowQuickEntry) { processQuickEntryRequestIfNeeded() }
        .onChange(of: shouldShowReport) { processReportRequestIfNeeded() }
        .onChange(of: showOnboarding) { _, isPresented in
            handleOverlayStateChange(isPresented: isPresented)
            if !showOnboarding {
                processQuickEntryRequestIfNeeded()
                processReportRequestIfNeeded()
                presentPendingForegroundReportIfPossible()
            }
        }
        .onChange(of: presentedSheet) { _, destination in
            handleOverlayStateChange(isPresented: destination != nil)
            if destination == nil {
                presentPendingForegroundReportIfPossible()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                processQuickEntryRequestIfNeeded()
                processReportRequestIfNeeded()
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }


    @ViewBuilder
    private var customTabBar: some View {
        if #available(iOS 26.0, *) {
            modernTabBar
        } else {
            legacyTabBar
        }
    }

    @available(iOS 26.0, *)
    private var modernTabBar: some View {
        // iOS 26 的自定义 glassEffect 会强制生成方向性投影，无法与内容保持同心。
        // 底栏改用单一系统材质基底；页面内其他控制仍使用原生 Liquid Glass。
        HStack(spacing: 6) {
            modernTabButton(icon: "book.fill", title: "账本", tag: 0)
            modernTabButton(icon: "chart.pie.fill", title: "预算", tag: 1)

            Button(action: performPrimaryAction) {
                VStack(spacing: 3) {
                    if reduceMotion {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                    } else {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .symbolEffect(.bounce, value: isQuickEntryPresented)
                    }
                    Text("记一笔")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .contentShape(Rectangle())
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(DesignSystem.primaryColor)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.20), lineWidth: 1)
                }
            }
            .buttonStyle(FloatingActionButtonStyle())
            .accessibilityLabel("快速记账")
            .accessibilityIdentifier("mainTab.quickEntry")

            modernTabButton(icon: "chart.bar.fill", title: "报表", tag: 3)
            modernTabButton(icon: "building.columns.fill", title: "资产", tag: 4)
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DesignSystem.borderColor.opacity(0.9), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var legacyTabBar: some View {
        HStack {
            legacyTabButton(icon: "book.fill", title: "账本", tag: 0)
            legacyTabButton(icon: "chart.pie.fill", title: "预算", tag: 1)

            // B 方向中央快捷入口：实体方圆按钮，不使用双层圆环、渐变或发光。
            Button(action: performPrimaryAction) {
                VStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 42)
                        .background(DesignSystem.primaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                    Text("记一笔")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(DesignSystem.primaryColor)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(FloatingActionButtonStyle())
            .accessibilityLabel("快速记账")
            .accessibilityIdentifier("mainTab.quickEntry")

            legacyTabButton(icon: "chart.bar.fill", title: "报表", tag: 3)

            legacyTabButton(icon: "building.columns.fill", title: "资产", tag: 4)
        }
        .padding(.horizontal, 8)
        .padding(.top, 9)
        .padding(.bottom, 5)
        .background {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(DesignSystem.cardBackground)

                Rectangle()
                    .fill(DesignSystem.borderColor)
                .frame(height: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 12, y: -4)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func processQuickEntryRequestIfNeeded() {
        guard shouldShowQuickEntry, hasCompletedOnboarding, !showOnboarding else { return }
        guard QuickEntryRoute.consume() else { return }
        presentedSheet = .quickEntry
    }

    private func processReportRequestIfNeeded() {
        guard shouldShowReport, hasCompletedOnboarding, !showOnboarding else { return }
        shouldShowReport = false
        guard let request = ReportRoute.consume() else { return }

        switch request.resolvedPresentation {
        case .reportTab:
            tabReportRequest = request
            selectTab(3, providesHaptic: false)
        case .foregroundSheet:
            pendingForegroundReport = request
            presentPendingForegroundReportIfPossible()
        }
    }

    private func presentPendingForegroundReportIfPossible() {
        guard let request = pendingForegroundReport,
              hasCompletedOnboarding,
              !showOnboarding,
              presentedSheet == nil else { return }
        pendingForegroundReport = nil
        presentedSheet = .deliveredReport(request)
    }

    private func handleDeepLink(_ url: URL) {
        guard let route = AppDeepLink(url: url) else { return }
        switch route {
        case .quickEntry:
            shouldShowQuickEntry = true
            processQuickEntryRequestIfNeeded()
        case .report(let period):
            ReportRoute.requestCurrent(period: period)
            processReportRequestIfNeeded()
        }
    }

    /// 底栏中央按钮在每个 tab 上都只做一件事：记一笔。
    /// 它过去在资产页会改成弹菜单，同一颗按钮两种行为；而「添加资金项」
    /// 本来就在资产页右上角，重复一遍只是把主操作变得不可预期。
    private func performPrimaryAction() {
        showTabBarAndResetIdleTimer()
        HapticManager.impact(.medium)
        presentedSheet = .quickEntry
    }

    private var isQuickEntryPresented: Bool {
        presentedSheet == .quickEntry
    }

    private func showTabBarAndResetIdleTimer() {
        // 主导航始终可见，避免用户在阅读或辅助功能操作中失去返回路径。
    }

    private func handleOverlayStateChange(isPresented: Bool) {
        // Sheet 会自行阻止底栏交互；无需隐藏主导航。
    }

    private func prepareForegroundReportUITestIfNeeded() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let marker = arguments.firstIndex(of: "-uiTestForegroundReport"),
              arguments.indices.contains(marker + 1),
              let period = uiTestReportPeriod(arguments[marker + 1]),
              pendingForegroundReport == nil,
              presentedSheet == nil else { return }
        if arguments.contains("-uiTestForegroundReportWhileQuickEntry") {
            presentedSheet = .quickEntry
        }
        pendingForegroundReport = ReportRoute.Request(
            period: period,
            target: .scheduled(deliveredAt: Date()),
            presentation: .foregroundSheet
        )
        presentPendingForegroundReportIfPossible()
#endif
    }

#if DEBUG
    private func uiTestReportPeriod(_ rawValue: String) -> ReportPeriod? {
        switch rawValue {
        case "daily": return .daily
        case "weekly": return .weekly
        case "monthly": return .monthly
        case "yearly": return .yearly
        case "payCycle": return .payCycle
        default: return nil
        }
    }
#endif

    private func selectTab(_ tag: Int, providesHaptic: Bool = true) {
        showTabBarAndResetIdleTimer()
        guard selectedTab != tag else { return }
        if providesHaptic {
            HapticManager.selection()
        }
        // 进资产页不再强制重新上锁：进后台时已经锁了（见 AppRootView），
        // 前台来回切 tab 还要求重新过一次 Face ID，只是把解锁成本乘上切换次数。

        // 页面和状态立即切换；图标自身的局部 animation 负责缩放，
        // 避免把玻璃材质或整页重排放进全局动画事务。
        selectedTab = tag
        animatedSelectedTab = tag
    }

    @available(iOS 26.0, *)
    private func modernTabButton(icon: String, title: String, tag: Int) -> some View {
        let isSelected = selectedTab == tag
        let isAnimatedSelected = animatedSelectedTab == tag
        return Button {
            selectTab(tag)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.title3.weight(isSelected ? .semibold : .regular))
                    .scaleEffect(isAnimatedSelected && !reduceMotion ? 1.08 : 1)
                    .animation(
                        reduceMotion ? nil : DesignSystem.glassSelectionAnimation,
                        value: isAnimatedSelected
                    )
                Text(title)
                    .font(.caption2.weight(isSelected ? .semibold : .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .contentShape(Rectangle())
            .foregroundStyle(isSelected ? DesignSystem.primaryColor : DesignSystem.textSecondary)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? DesignSystem.primaryColor.opacity(0.15) : .clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? .white.opacity(0.42) : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(tabAccessibilityIdentifier(for: tag))
    }

    private func legacyTabButton(icon: String, title: String, tag: Int) -> some View {
        Button {
            selectTab(tag)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3.weight(selectedTab == tag ? .semibold : .regular))
                    .scaleEffect(selectedTab == tag && !reduceMotion ? 1.04 : 1)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .scaleEffect(selectedTab == tag && !reduceMotion ? 1 : 0.96)
            .foregroundStyle(
                selectedTab == tag
                ? DesignSystem.primaryColor
                : DesignSystem.textTertiary
            )
            // 仅对当前按钮的几个简单属性做短动画，不发生跨视图布局计算。
            .animation(reduceMotion ? nil : DesignSystem.quickAnimation, value: selectedTab == tag)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(selectedTab == tag ? .isSelected : [])
        .accessibilityIdentifier(tabAccessibilityIdentifier(for: tag))
    }

    private func tabAccessibilityIdentifier(for tag: Int) -> String {
        switch tag {
        case 0: return "mainTab.ledger"
        case 1: return "mainTab.budget"
        case 3: return "mainTab.report"
        case 4: return "mainTab.assets"
        default: return "mainTab.unknown"
        }
    }
}
