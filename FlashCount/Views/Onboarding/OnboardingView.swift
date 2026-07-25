import SwiftUI

/// 首次启动引导页
struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isPresented: Bool
    var onComplete: () -> Void = {}

    private let features: [(icon: String, title: String, desc: String, color: Color)] = [
        ("bolt.fill", "极速记账", "打开即记，3 秒搞定", DesignSystem.primaryColor),
        ("chart.bar.fill", "多维报表", "日报、周报、月报、年报和发薪周期报", DesignSystem.primaryColor),
        ("iphone.and.arrow.forward", "实物资产", "追踪日均成本，主打长期主义", DesignSystem.primaryColor),
        ("eye.slash.fill", "隐私至上", "数据全在本地，余额一键隐藏", DesignSystem.primaryColor),
    ]

    var body: some View {
        ZStack {
            AmbientBackground(accent: DesignSystem.primaryColor)

            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "bolt.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(DesignSystem.primaryColor)
                        Text("FlashCount")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(DesignSystem.textPrimary)
                        Text("你的私人财务分析师")
                            .font(.subheadline)
                            .foregroundStyle(DesignSystem.textSecondary)
                    }
                    .padding(.top, 36)

                    VStack(spacing: 16) {
                        ForEach(features, id: \.title) { feature in
                            HStack(spacing: 16) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(feature.color.opacity(0.15))
                                        .frame(width: 48, height: 48)
                                    Image(systemName: feature.icon)
                                        .font(.title3)
                                        .foregroundStyle(feature.color)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(DesignSystem.textPrimary)
                                    Text(feature.desc)
                                        .font(.caption)
                                        .foregroundStyle(DesignSystem.textSecondary)
                                }
                                Spacer()
                            }
                        }
                    }

                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "lightbulb.fill").font(.caption).foregroundStyle(DesignSystem.primaryColor)
                            Text("小贴士").font(.caption.weight(.semibold)).foregroundStyle(DesignSystem.primaryColor)
                        }
                        Text("添加锁屏 Widget 或设置 Back Tap\n让记账快人一步；进入 App 后可在设置中查看教程")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(DesignSystem.softFill)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onComplete()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.4)) { isPresented = false }
                } label: {
                    Text("开始使用")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(DesignSystem.primaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
        }
    }
}

/// 快捷方式教程（可随时打开）
struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss

    private let tutorials: [(step: String, icon: String, title: String, detail: String)] = [
        ("1", "square.grid.2x2", "桌面 Widget",
         "长按桌面 → 点左上角 ＋ → 搜索 FlashCount → 添加小组件"),
        ("2", "lock.fill", "锁屏 Widget",
         "长按锁屏 → 自定义 → 添加小组件 → 搜索 FlashCount"),
        ("3", "hand.tap.fill", "轻点背面",
         "设置 → 辅助功能 → 触控 → 轻点背面 → 轻点两下 → 选择「快速记账」"),
        ("4", "mic.fill", "Siri 语音",
         "对 Siri 说「用 FlashCount 快速记账」"),
        ("5", "square.and.arrow.up", "快捷指令",
         "打开 iOS 快捷指令 App → 搜索 FlashCount → 添加到桌面或主屏幕"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // 头部
                        VStack(spacing: 8) {
                            Text("快捷记账指南")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(DesignSystem.textPrimary)
                            Text("让记账不再需要翻找 App")
                                .font(.subheadline)
                                .foregroundStyle(DesignSystem.textSecondary)
                        }
                        .padding(.top, 8)

                        // 教程步骤
                        ForEach(tutorials, id: \.step) { tutorial in
                            HStack(alignment: .top, spacing: 16) {
                                // 步骤编号
                                ZStack {
                                    Circle()
                                        .fill(DesignSystem.primaryColor.opacity(0.2))
                                        .frame(width: 36, height: 36)
                                    Text(tutorial.step)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(DesignSystem.primaryColor)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Image(systemName: tutorial.icon)
                                            .font(.caption)
                                            .foregroundStyle(DesignSystem.primaryColor)
                                        Text(tutorial.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(DesignSystem.textPrimary)
                                    }
                                    Text(tutorial.detail)
                                        .font(.caption)
                                        .foregroundStyle(DesignSystem.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                            }
                            .padding()
                            .background(DesignSystem.softFill)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DesignSystem.borderColor))
                        }

                        // 底部提示
                        Text("设置完成后，记账只需 1 秒")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.textTertiary)
                            .padding(.top, 8)
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(DesignSystem.primaryColor)
                }
            }
        }
    }
}
