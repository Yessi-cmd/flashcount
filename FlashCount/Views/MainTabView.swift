import SwiftUI
import SwiftData

/// 主标签栏视图
struct MainTabView: View {
    @Query(sort: \CashPoolItem.sortOrder) private var cashPoolItems: [CashPoolItem]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var privacyLock: PrivacyLockService
    @State private var selectedTab: Int
    @State private var showQuickEntry = false
    @State private var showAddCashPoolItem = false
    @State private var showPlusActions = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(QuickEntryRoute.requestKey) private var shouldShowQuickEntry = false
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
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                LedgerView()
                    .tag(0)
                BudgetView()
                    .tag(1)
                Color.clear // 中间占位 (记账按钮)
                    .tag(2)
                ReportView()
                    .tag(3)
                AssetDashboardView(isActive: selectedTab == 4)
                    .tag(4)
            }
            .tint(DesignSystem.primaryColor)

            // 自定义底部标签栏
            customTabBar
        }
        .sheet(isPresented: $showQuickEntry) {
            QuickEntryView()
        }
        .sheet(isPresented: $showAddCashPoolItem) {
            AddCashPoolItemView(nextSortOrder: cashPoolItems.count)
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding) {
                hasCompletedOnboarding = true
            }
        }
        .confirmationDialog("快捷操作", isPresented: $showPlusActions) {
            Button("记一笔") {
                showQuickEntry = true
            }
            Button("添加资金项") {
                showAddCashPoolItem = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("选择要添加的内容")
        }
        .onAppear {
            if !hasCompletedOnboarding {
                showOnboarding = true
            }
            processQuickEntryRequestIfNeeded()
        }
        .onChange(of: shouldShowQuickEntry) { processQuickEntryRequestIfNeeded() }
        .onChange(of: showOnboarding) {
            if !showOnboarding {
                processQuickEntryRequestIfNeeded()
            }
        }
    }


    private var customTabBar: some View {
        HStack {
            tabButton(icon: "book.fill", title: "账本", tag: 0)
            tabButton(icon: "chart.pie.fill", title: "预算", tag: 1)

            // B 方向中央快捷入口：实体方圆按钮，不使用双层圆环、渐变或发光。
            Button {
                HapticManager.impact(.medium)
                if selectedTab == 4 {
                    showPlusActions = true
                } else {
                    showQuickEntry = true
                }
            } label: {
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

            tabButton(icon: "chart.bar.fill", title: "报表", tag: 3)

            tabButton(icon: "building.columns.fill", title: "资产", tag: 4)
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
        guard shouldShowQuickEntry, !showOnboarding else { return }
        shouldShowQuickEntry = false
        showQuickEntry = true
    }

    private func tabButton(icon: String, title: String, tag: Int) -> some View {
        Button {
            guard selectedTab != tag else { return }
            HapticManager.selection()
            if tag == 4 {
                // 资产页每次从标签栏进入都从隐藏态开始，避免之前的会话解锁状态造成误展示。
                privacyLock.lock()
            }
            // 不使用全局 withAnimation，防止动画事务传播到整张页面。
            selectedTab = tag
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
    }
}
