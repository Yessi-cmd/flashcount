import SwiftUI

/// 首次启动引导页
struct OnboardingView: View {
    @Binding var isPresented: Bool

    private let features: [(icon: String, title: String, desc: String, color: Color)] = [
        ("bolt.fill", "极速记账", "打开即记，3 秒搞定", .orange),
        ("chart.bar.fill", "周报月报", "消费趋势、分类排行、智能洞察", Color(red: 0.4, green: 0.49, blue: 0.92)),
        ("iphone.and.arrow.forward", "实物资产", "追踪日均成本，主打长期主义", .cyan),
        ("eye.slash.fill", "隐私至上", "数据全在本地，余额一键隐藏", .green),
    ]

    var body: some View {
        ZStack {
            DesignSystem.surfaceBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo + Title
                VStack(spacing: 12) {
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(DesignSystem.primaryGradient)
                    Text("FlashCount")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)
                    Text("你的私人财务分析师")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.bottom, 40)

                // 功能亮点
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
                                    .foregroundStyle(.white)
                                Text(feature.desc)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                // 快捷方式提示
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb.fill").font(.caption).foregroundStyle(.yellow)
                        Text("小贴士").font(.caption.weight(.semibold)).foregroundStyle(.yellow)
                    }
                    Text("添加锁屏 Widget 或设置 Back Tap\n让记账快人一步！进入 App 后点 ❓ 查看教程")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(.yellow.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)

                Spacer().frame(height: 24)

                // 开始按钮
                Button {
                    withAnimation(.spring(response: 0.4)) {
                        isPresented = false
                    }
                } label: {
                    Text("开始使用 🚀")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(DesignSystem.primaryGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
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
        ("3", "hand.tap.fill", "Back Tap 背部轻拍",
         "设置 → 辅助功能 → 触控 → 轻点背面 → 选择 FlashCount 快捷指令"),
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
                            Text("⚡ 快捷记账指南")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                            Text("让记账不再需要翻找 App")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.5))
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
                                            .foregroundStyle(.white)
                                    }
                                    Text(tutorial.detail)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.6))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                            }
                            .padding()
                            .background(.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.06)))
                        }

                        // 底部提示
                        Text("设置完成后，记账只需 1 秒 ⚡")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
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
