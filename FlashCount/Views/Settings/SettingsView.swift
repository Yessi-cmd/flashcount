import SwiftUI
import SwiftData

/// 设置页面
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appearance") private var appearance = "system"
    @State private var showTutorial = false
    @State private var showRecurringRules = false

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                List {
                    // 外观
                    Section {
                        Picker("外观", selection: $appearance) {
                            Text("跟随系统").tag("system")
                            Text("深色").tag("dark")
                            Text("浅色").tag("light")
                        }
                        .foregroundStyle(.white)
                    } header: {
                        Text("外观设置").foregroundStyle(.white.opacity(0.5))
                    }
                    .listRowBackground(Color.white.opacity(0.04))

                    // 快捷方式 + 教程
                    Section {
                        Button {
                            showTutorial = true
                        } label: {
                            HStack {
                                Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
                                VStack(alignment: .leading) {
                                    Text("快捷记账教程").font(.subheadline).foregroundStyle(.white)
                                    Text("锁屏 Widget / Back Tap / Siri 设置方法").font(.caption).foregroundStyle(.white.opacity(0.4))
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.white.opacity(0.3))
                            }
                        }
                        Button {
                            showRecurringRules = true
                        } label: {
                            HStack {
                                Image(systemName: "repeat").foregroundStyle(DesignSystem.primaryColor)
                                VStack(alignment: .leading) {
                                    Text("周期性规则").font(.subheadline).foregroundStyle(.white)
                                    Text("管理自动入账的周期规则").font(.caption).foregroundStyle(.white.opacity(0.4))
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.white.opacity(0.3))
                            }
                        }
                    } header: {
                        Text("快捷入口").foregroundStyle(.white.opacity(0.5))
                    }
                    .listRowBackground(Color.white.opacity(0.04))

                    // 数据管理
                    Section {
                        Button {
                            exportData()
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.up").foregroundStyle(DesignSystem.primaryColor)
                                Text("导出数据 (JSON)").foregroundStyle(.white)
                            }
                        }
                    } header: {
                        Text("数据管理").foregroundStyle(.white.opacity(0.5))
                    }
                    .listRowBackground(Color.white.opacity(0.04))

                    // 关于
                    Section {
                        HStack {
                            Text("版本").foregroundStyle(.white)
                            Spacer()
                            Text("1.0.0").foregroundStyle(.white.opacity(0.4))
                        }
                        HStack {
                            Text("开发者").foregroundStyle(.white)
                            Spacer()
                            Text("FlashCount OSS").foregroundStyle(.white.opacity(0.4))
                        }
                        Link(destination: URL(string: "https://github.com")!) {
                            HStack {
                                Text("GitHub 仓库").foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "arrow.up.right.square").foregroundStyle(.white.opacity(0.4))
                            }
                        }
                    } header: {
                        Text("关于").foregroundStyle(.white.opacity(0.5))
                    }
                    .listRowBackground(Color.white.opacity(0.04))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showTutorial) {
                TutorialView()
            }
            .sheet(isPresented: $showRecurringRules) {
                NavigationStack {
                    RecurringRulesView()
                }
            }
        }
    }

    private func exportData() {
        // TODO: JSON 导出
    }
}
