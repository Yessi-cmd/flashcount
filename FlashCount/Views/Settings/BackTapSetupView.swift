import AppIntents
import SwiftUI

/// 「轻点背面」快捷记账的设置引导。
struct BackTapSetupView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: DesignSystem.space12) {
                        Image(systemName: "hand.tap.fill")
                            .font(.largeTitle)
                            .foregroundStyle(DesignSystem.primaryColor)
                            .accessibilityHidden(true)

                        Text("轻点两下，立即记账")
                            .font(.title2.bold())
                            .foregroundStyle(DesignSystem.textPrimary)

                        Text("付款完成后轻点 iPhone 背面两下，系统会运行 FlashCount 的「快速记账」快捷指令并直接打开记账页。")
                            .font(.body)
                            .foregroundStyle(DesignSystem.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.space12)
                }
                .listRowBackground(DesignSystem.cardBackground)

                Section {
                    VStack(alignment: .leading, spacing: DesignSystem.space12) {
                        Text("先确认「快速记账」已出现在 FlashCount 的 App 快捷指令中。")
                            .font(.body)
                            .foregroundStyle(DesignSystem.textSecondary)

                        ShortcutsLink {
                            FlashCountShortcuts.refreshSystemRegistration()
                        }
                        .shortcutsLinkStyle(.automaticOutline)
                        .accessibilityIdentifier("backTapSetup.shortcutsLink")
                    }
                    .padding(.vertical, DesignSystem.space4)
                } header: {
                    Text("准备快捷指令")
                        .foregroundStyle(DesignSystem.textSecondary)
                } footer: {
                    Text("如果系统没有立即显示，请打开一次 FlashCount 后再返回这里刷新。")
                        .foregroundStyle(DesignSystem.textTertiary)
                }
                .listRowBackground(DesignSystem.cardBackground)

                Section {
                    HStack(alignment: .top, spacing: DesignSystem.space12) {
                        stepNumber("1")
                        VStack(alignment: .leading, spacing: DesignSystem.space4) {
                            Text("打开系统设置")
                                .font(.headline)
                                .foregroundStyle(DesignSystem.textPrimary)
                            Text("进入「辅助功能 → 触控」。")
                                .font(.body)
                                .foregroundStyle(DesignSystem.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)

                    HStack(alignment: .top, spacing: DesignSystem.space12) {
                        stepNumber("2")
                        VStack(alignment: .leading, spacing: DesignSystem.space4) {
                            Text("选择轻点两下")
                                .font(.headline)
                                .foregroundStyle(DesignSystem.textPrimary)
                            Text("进入「轻点背面」，然后选择「轻点两下」。")
                                .font(.body)
                                .foregroundStyle(DesignSystem.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)

                    HStack(alignment: .top, spacing: DesignSystem.space12) {
                        stepNumber("3")
                        VStack(alignment: .leading, spacing: DesignSystem.space4) {
                            Text("绑定快速记账")
                                .font(.headline)
                                .foregroundStyle(DesignSystem.textPrimary)
                            Text("滚动到「快捷指令」区域，选择 FlashCount 的「快速记账」。")
                                .font(.body)
                                .foregroundStyle(DesignSystem.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                } header: {
                    Text("绑定轻点背面")
                        .foregroundStyle(DesignSystem.textSecondary)
                } footer: {
                    Text("出于隐私与防误触要求，iOS 必须由你亲自在系统设置中完成绑定，FlashCount 无法代为修改。")
                        .foregroundStyle(DesignSystem.textTertiary)
                }
                .listRowBackground(DesignSystem.cardBackground)

                Section {
                    Label {
                        Text("支付完成后保持设备解锁，轻点背面两下；FlashCount 打开后输入金额并确认即可。")
                            .font(.body)
                            .foregroundStyle(DesignSystem.textSecondary)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DesignSystem.primaryColor)
                    }
                } header: {
                    Text("开始使用")
                        .foregroundStyle(DesignSystem.textSecondary)
                }
                .listRowBackground(DesignSystem.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(DesignSystem.surfaceBackground)
            .navigationTitle("轻点背面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成", action: dismiss.callAsFunction)
                        .foregroundStyle(DesignSystem.primaryColor)
                }
            }
        }
    }

    private func stepNumber(_ number: String) -> some View {
        Text(number)
            .font(.headline)
            .foregroundStyle(DesignSystem.primaryColor)
            .frame(width: 36, height: 36)
            .background(DesignSystem.softFill)
            .clipShape(.circle)
            .accessibilityHidden(true)
    }
}
