import SwiftUI
import SwiftData

/// 主标签栏视图
struct MainTabView: View {
    @Query(sort: \CashPoolItem.sortOrder) private var cashPoolItems: [CashPoolItem]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab = 0
    @State private var showQuickEntry = false
    @State private var showAddCashPoolItem = false
    @State private var showPlusActions = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(QuickEntryRoute.requestKey) private var shouldShowQuickEntry = false
    @State private var showOnboarding = false

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
            OnboardingView(isPresented: $showOnboarding)
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
                hasCompletedOnboarding = true
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

            // 中间加号按钮
            Button {
                HapticManager.impact(.medium)
                if selectedTab == 4 {
                    showPlusActions = true
                } else {
                    showQuickEntry = true
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(DesignSystem.cardBackground)
                        .frame(width: 68, height: 68)
                        .overlay {
                            Circle()
                                .stroke(DesignSystem.borderColor.opacity(0.8), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.10), radius: 16, y: 7)

                    Circle()
                        .fill(DesignSystem.primaryGradient)
                        .frame(width: 58, height: 58)
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.50), lineWidth: 1)
                        }
                        .shadow(color: DesignSystem.primaryColor.opacity(0.35), radius: 12, y: 5)

                    Image(systemName: "plus")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }
                .offset(y: -19)
            }
            .buttonStyle(FloatingActionButtonStyle())
            .accessibilityLabel("快速记账")

            tabButton(icon: "chart.bar.fill", title: "报表", tag: 3)

            tabButton(icon: "building.columns.fill", title: "资产", tag: 4)
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 5)
        .background {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.ultraThinMaterial)

                LinearGradient(
                    colors: [.white.opacity(0.55), DesignSystem.borderColor.opacity(0.45), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 1)
            }
            // 背景和分割高光均在按钮下方绘制，不会再穿过主加号。
            .shadow(color: .black.opacity(0.08), radius: 18, y: -6)
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
            // 不使用全局 withAnimation，防止动画事务传播到整张页面。
            selectedTab = tag
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .scaleEffect(selectedTab == tag && !reduceMotion ? 1.08 : 1)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill(DesignSystem.primaryColor.opacity(0.12))
                    .overlay {
                        Capsule()
                            .stroke(DesignSystem.primaryColor.opacity(0.14), lineWidth: 1)
                    }
                    .opacity(selectedTab == tag ? 1 : 0)
                    .scaleEffect(selectedTab == tag ? 1 : 0.92)
            }
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
