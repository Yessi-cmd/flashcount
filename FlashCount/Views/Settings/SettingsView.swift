import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 设置页面
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"
    @State private var showTutorial = false
    @State private var showRecurringRules = false
    @State private var repairResult: String?
    @State private var showRepairResult = false
    @State private var showExportShare = false
    @State private var exportFileURL: URL?
    @State private var showImportPicker = false
    @State private var importResult: String?
    @State private var showImportResult = false

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
                                VStack(alignment: .leading) {
                                    Text("导出数据 (JSON)").font(.subheadline).foregroundStyle(.white)
                                    Text("备份实物资产等数据到文件").font(.caption).foregroundStyle(.white.opacity(0.4))
                                }
                            }
                        }
                        Button {
                            showImportPicker = true
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.down").foregroundStyle(.green)
                                VStack(alignment: .leading) {
                                    Text("导入数据 (JSON)").font(.subheadline).foregroundStyle(.white)
                                    Text("从备份文件恢复数据").font(.caption).foregroundStyle(.white.opacity(0.4))
                                }
                            }
                        }
                        Button {
                            let service = DataRepairService(modelContext: modelContext)
                            let report = service.runRepair()
                            repairResult = report.summary
                            showRepairResult = true
                            if report.totalFixed > 0 {
                                HapticManager.success()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "wrench.and.screwdriver.fill").foregroundStyle(.orange)
                                VStack(alignment: .leading) {
                                    Text("数据自检修复").font(.subheadline).foregroundStyle(.white)
                                    Text("检查并修复异常数据").font(.caption).foregroundStyle(.white.opacity(0.4))
                                }
                            }
                        }
                    } header: {
                        Text("数据管理").foregroundStyle(.white.opacity(0.5))
                    } footer: {
                        Text("⚠️ 卸载 App 会删除所有本地数据，建议定期导出备份")
                            .font(.caption2).foregroundStyle(.orange.opacity(0.6))
                    }
                    .listRowBackground(Color.white.opacity(0.04))

                    // 关于
                    Section {
                        HStack {
                            Text("版本").foregroundStyle(.white)
                            Spacer()
                            Text("1.2.0").foregroundStyle(.white.opacity(0.4))
                        }
                        HStack {
                            Text("开发者").foregroundStyle(.white)
                            Spacer()
                            Text("Yessi").foregroundStyle(.white.opacity(0.4))
                        }
                        Link(destination: URL(string: "https://github.com/Yessi-cmd/flashcount")!) {
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(DesignSystem.primaryColor)
                }
            }
            .sheet(isPresented: $showTutorial) {
                TutorialView()
            }
            .sheet(isPresented: $showRecurringRules) {
                NavigationStack {
                    RecurringRulesView()
                }
            }
            .sheet(isPresented: $showExportShare) {
                if let url = exportFileURL {
                    ShareSheet(items: [url])
                }
            }
            .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.json]) { result in
                importData(result: result)
            }
            .alert("数据自检结果", isPresented: $showRepairResult) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(repairResult ?? "")
            }
            .alert("导入结果", isPresented: $showImportResult) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(importResult ?? "")
            }
        }
    }

    private func exportData() {
        let service = DataBackupService(modelContext: modelContext)
        do {
            let url = try service.exportToFile()
            exportFileURL = url
            showExportShare = true
            HapticManager.success()
        } catch {
            repairResult = "导出失败：\(error.localizedDescription)"
            showRepairResult = true
        }
    }

    private func importData(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                importResult = "无法访问文件"
                showImportResult = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let service = DataBackupService(modelContext: modelContext)
            do {
                let report = try service.importJSON(from: url)
                importResult = report.summary
                showImportResult = true
                HapticManager.success()
            } catch {
                importResult = "导入失败：\(error.localizedDescription)"
                showImportResult = true
            }
        case .failure(let error):
            importResult = "文件选择失败：\(error.localizedDescription)"
            showImportResult = true
        }
    }
}

// MARK: - ShareSheet (UIKit wrapper)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
