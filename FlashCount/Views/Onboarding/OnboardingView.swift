import SwiftUI
import SwiftData

/// 首次启动引导页
///
/// 这里过去只是四条功能介绍加一个「开始使用」，然后把人丢进空账本。
/// 问题在于：预算和报表整套口径都建立在发薪周期上，默认每月 1 日；
/// 15 号发薪的用户在自己翻到设置之前，看到的每一个周期数字都是错的，
/// 而界面不会有任何提示。所以引导必须问一次发薪日——这是个静默错误，
/// 比少介绍一个功能严重得多。预算是顺带的第二个输入，可以跳过。
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isPresented: Bool
    var onComplete: () -> Void = {}

    @AppStorage("payday") private var payday = 1

    @State private var draftPayday = 1
    @State private var budgetText = ""
    @State private var saveError: String?

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

                    paydaySetup

                    budgetSetup

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
                        Text("设置 Back Tap 或 Siri 快捷指令\n让记账快人一步；进入 App 后可在设置中查看教程")
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
                    complete()
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
        .onAppear {
            draftPayday = payday
        }
        .alert("预算未能保存", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好的", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var paydaySetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("你每月几号发薪？", systemImage: "calendar.badge.clock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.textPrimary)

            Stepper(value: $draftPayday, in: 1...31) {
                Text("每月 \(draftPayday) 日")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(DesignSystem.primaryColor)
            }
            .accessibilityIdentifier("onboarding.payday")

            Text("预算、报表和「本周期」都按这一天切分。某个月没有这一天时自动用当月最后一天。以后可在设置里改。")
                .font(.caption)
                .foregroundStyle(DesignSystem.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(DesignSystem.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignSystem.primaryColor.opacity(0.24), lineWidth: 1)
        )
    }

    private var budgetSetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("本周期日常预算（可跳过）", systemImage: "chart.pie.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.textPrimary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("¥")
                    .font(.title3)
                    .foregroundStyle(DesignSystem.textSecondary)
                TextField("留空则先不设预算", text: $budgetText)
                    .keyboardType(.decimalPad)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(DesignSystem.textPrimary)
                    .accessibilityIdentifier("onboarding.budget")
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(DesignSystem.softFill)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 8) {
                ForEach(["3000", "5000", "8000"], id: \.self) { amount in
                    Button {
                        budgetText = amount
                        HapticManager.selection()
                    } label: {
                        Text("¥\(amount)")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(DesignSystem.softFill)
                            .foregroundStyle(DesignSystem.textSecondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("填了就能立刻看到每天可花多少；之后在预算页随时调整。")
                .font(.caption)
                .foregroundStyle(DesignSystem.textSecondary)
        }
        .padding()
        .background(DesignSystem.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignSystem.borderColor, lineWidth: 1)
        )
    }

    /// 发薪日先落盘，预算按它所在的周期建立——顺序颠倒会把预算挂到错误的周期上。
    private func complete() {
        payday = draftPayday

        let trimmed = budgetText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            switch MoneyValidation.parse(trimmed, requirement: .positive) {
            case .success(let amount):
                let cycle = PayCycleService.cycle(payday: draftPayday)
                modelContext.insert(
                    Budget(
                        monthlyLimit: amount,
                        year: cycle.budgetYear,
                        month: cycle.budgetMonth
                    )
                )
                if let error = safeSave(modelContext) {
                    // 预算没存上不该拦住用户进入 App：发薪日已经生效，预算稍后可补。
                    saveError = error
                    return
                }
            case .failure(let error):
                saveError = error.errorDescription ?? "预算金额无效"
                return
            }
        }

        onComplete()
        withAnimation(reduceMotion ? nil : .spring(response: 0.4)) { isPresented = false }
    }
}

/// 快捷方式教程（可随时打开）
struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss

    private let tutorials: [(step: String, icon: String, title: String, detail: String)] = [
        ("1", "hand.tap.fill", "轻点背面",
         "设置 → 辅助功能 → 触控 → 轻点背面 → 轻点两下 → 选择「快速记账」"),
        ("2", "mic.fill", "Siri 语音",
         "对 Siri 说「用 FlashCount 快速记账」"),
        ("3", "square.and.arrow.up", "快捷指令",
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
