import SwiftUI
import SwiftData

/// 主标签栏视图
struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var showQuickEntry = false
    @State private var showAddAsset = false
    @State private var showTutorial = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
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
                AssetDashboardView()
                    .tag(4)
            }
            .tint(DesignSystem.primaryColor)

            // 自定义底部标签栏
            customTabBar
        }
        .sheet(isPresented: $showQuickEntry) {
            QuickEntryView()
        }
        .sheet(isPresented: $showAddAsset) {
            AddAssetView()
        }
        .sheet(isPresented: $showTutorial) {
            TutorialView()
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
        .onAppear {
            if !hasCompletedOnboarding {
                showOnboarding = true
                hasCompletedOnboarding = true
            }
        }
    }

    private var customTabBar: some View {
        HStack {
            tabButton(icon: "book.fill", title: "账本", tag: 0)
            tabButton(icon: "chart.pie.fill", title: "预算", tag: 1)

            // 中间加号按钮（资产页时添加资产，其他页记账）
            Button {
                if selectedTab == 4 {
                    showAddAsset = true
                } else {
                    showQuickEntry = true
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(DesignSystem.primaryGradient)
                        .frame(width: 56, height: 56)
                        .shadow(color: DesignSystem.primaryColor.opacity(0.4), radius: 10, y: 4)

                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .offset(y: -16)
            }

            tabButton(icon: "chart.bar.fill", title: "报表", tag: 3)

            // 资产 Tab + 教程按钮叠加
            ZStack(alignment: .topTrailing) {
                tabButton(icon: "building.columns.fill", title: "资产", tag: 4)
                Button {
                    showTutorial = true
                } label: {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .offset(x: 4, y: -2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(icon: String, title: String, tag: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                selectedTab = tag
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .symbolEffect(.bounce, value: selectedTab == tag)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(
                selectedTab == tag
                ? DesignSystem.primaryColor
                : .white.opacity(0.4)
            )
        }
    }
}
