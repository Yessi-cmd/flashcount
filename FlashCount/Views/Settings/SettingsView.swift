import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 设置页面
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var privacyLock: PrivacyLockService
    @AppStorage("appearance") private var appearance = AppearancePreference.light.rawValue
    @AppStorage("payday") private var payday = 1
    @State private var showTutorial = false
    @State private var showRecurringRules = false
    @State private var showReminders = false
    @State private var showTemplates = false
    @State private var showCategoryManagement = false
    @State private var showOnboarding = false
    @State private var repairResult: String?
    @State private var showRepairResult = false
    @State private var showExportShare = false
    @State private var exportFileURL: URL?
    @State private var showImportPicker = false
    @State private var showCSVImportPicker = false
    @State private var importResult: String?
    @State private var showImportResult = false
    @State private var pendingImportURL: URL?
    @State private var importPreview: DataBackupService.BackupPreview?

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                List {
                    Section {
                        Button {
                            if privacyLock.isUnlocked {
                                privacyLock.lock()
                                HapticManager.selection()
                            } else {
                                privacyLock.requestReveal()
                            }
                        } label: {
                            HStack {
                                Image(systemName: privacyLock.isUnlocked ? "eye.fill" : "eye.slash.fill")
                                    .foregroundStyle(privacyLock.isUnlocked ? DesignSystem.primaryColor : DesignSystem.textSecondary)
                                VStack(alignment: .leading) {
                                    Text(privacyLock.isUnlocked ? "隐私金额当前可见" : "隐私金额当前隐藏")
                                        .font(.subheadline)
                                        .foregroundStyle(DesignSystem.textPrimary)
                                    Text(privacyLock.isUnlocked ? "点击立即隐藏收入和资产" : "确认并验证后，统一显示收入和资产")
                                        .font(.caption)
                                        .foregroundStyle(DesignSystem.textTertiary)
                                }
                                Spacer()
                                Text(privacyLock.isUnlocked ? "隐藏" : "显示")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(DesignSystem.primaryColor)
                            }
                        }
                    } header: {
                        Text("隐私").foregroundStyle(DesignSystem.textSecondary)
                    } footer: {
                        Text("显示前会先确认，再使用 Face ID、Touch ID 或设备密码验证。App 进入后台后自动隐藏。")
                            .font(.caption2)
                            .foregroundStyle(DesignSystem.textTertiary)
                    }
                    .listRowBackground(DesignSystem.cardBackground)

                    // 外观
                    Section {
                        Picker("外观", selection: $appearance) {
                            Text("浅色").tag(AppearancePreference.light.rawValue)
                            Text("跟随系统").tag(AppearancePreference.system.rawValue)
                            Text("深色").tag(AppearancePreference.dark.rawValue)
                        }
                        .foregroundStyle(DesignSystem.textPrimary)
                    } header: {
                        Text("外观设置").foregroundStyle(DesignSystem.textSecondary)
                    }
                    .listRowBackground(DesignSystem.cardBackground)

                    Section {
                        Stepper(value: $payday, in: 1...31) {
                            HStack {
                                Image(systemName: "calendar.badge.clock").foregroundStyle(DesignSystem.primaryColor)
                                VStack(alignment: .leading) {
                                    Text("发薪日").font(.subheadline).foregroundStyle(DesignSystem.textPrimary)
                                    Text("每月 \(payday) 日，预算按发薪周期计算").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                                }
                            }
                        }
                    } header: {
                        Text("预算周期").foregroundStyle(DesignSystem.textSecondary)
                    } footer: {
                        Text("如果某个月没有这一天，会自动使用当月最后一天。")
                            .font(.caption2).foregroundStyle(DesignSystem.textTertiary)
                    }
                    .listRowBackground(DesignSystem.cardBackground)

                    // 快捷方式 + 教程
                    Section {
                        Button {
                            showReminders = true
                        } label: {
                            HStack {
                                Image(systemName: "bell.badge.fill").foregroundStyle(DesignSystem.warningColor)
                                VStack(alignment: .leading) {
                                    Text("提醒事项").font(.subheadline).foregroundStyle(DesignSystem.textPrimary)
                                    Text("未来某天某时刻提醒，支持强提醒").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                            }
                        }
                        Button {
                            showTutorial = true
                        } label: {
                            HStack {
                                Image(systemName: "questionmark.circle.fill").foregroundStyle(DesignSystem.primaryColor)
                                VStack(alignment: .leading) {
                                    Text("快捷记账教程").font(.subheadline).foregroundStyle(DesignSystem.textPrimary)
                                    Text("锁屏 Widget / Back Tap / Siri 设置方法").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                            }
                        }
                        Button {
                            showOnboarding = true
                        } label: {
                            HStack {
                                Image(systemName: "sparkles").foregroundStyle(DesignSystem.primaryColor)
                                VStack(alignment: .leading) {
                                    Text("首次引导").font(.subheadline).foregroundStyle(DesignSystem.textPrimary)
                                    Text("FlashCount 功能亮点一览").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                            }
                        }
                        Button {
                            showRecurringRules = true
                        } label: {
                            HStack {
                                Image(systemName: "repeat").foregroundStyle(DesignSystem.primaryColor)
                                VStack(alignment: .leading) {
                                    Text("周期性规则").font(.subheadline).foregroundStyle(DesignSystem.textPrimary)
                                    Text("管理自动入账的周期规则").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                            }
                        }
                        Button {
                            showTemplates = true
                        } label: {
                            HStack {
                                Image(systemName: "bolt.fill").foregroundStyle(DesignSystem.warningColor)
                                VStack(alignment: .leading) {
                                    Text("记账模板").font(.subheadline).foregroundStyle(DesignSystem.textPrimary)
                                    Text("自定义快速记账模板").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                            }
                        }
                        Button {
                            showCategoryManagement = true
                        } label: {
                            HStack {
                                Image(systemName: "square.grid.3x3.square").foregroundStyle(DesignSystem.primaryColor)
                                VStack(alignment: .leading) {
                                    Text("分类管理").font(.subheadline).foregroundStyle(DesignSystem.textPrimary)
                                    Text("增改、排序、归档与合并收支分类").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                            }
                        }
                    } header: {
                        Text("快捷入口").foregroundStyle(DesignSystem.textSecondary)
                    }
                    .listRowBackground(DesignSystem.cardBackground)

                    // 数据管理
                    Section {
                        Button {
                            exportData()
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.up").foregroundStyle(DesignSystem.primaryColor)
                                VStack(alignment: .leading) {
                                    Text("导出数据 (JSON)").font(.subheadline).foregroundStyle(DesignSystem.textPrimary)
                                    Text("备份实物资产等数据到文件").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                                }
                            }
                        }
                        Button {
                            showImportPicker = true
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.down").foregroundStyle(DesignSystem.primaryColor)
                                VStack(alignment: .leading) {
                                    Text("导入数据 (JSON)").font(.subheadline).foregroundStyle(DesignSystem.textPrimary)
                                    Text("从备份文件恢复数据").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                                }
                            }
                        }
                        Button {
                            exportCSV()
                        } label: {
                            Label("导出账单 CSV", systemImage: "tablecells")
                        }
                        Button {
                            showCSVImportPicker = true
                        } label: {
                            Label("导入账单 CSV", systemImage: "tablecells.badge.ellipsis")
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
                                Image(systemName: "wrench.and.screwdriver.fill").foregroundStyle(DesignSystem.primaryColor)
                                VStack(alignment: .leading) {
                                    Text("数据自检修复").font(.subheadline).foregroundStyle(DesignSystem.textPrimary)
                                    Text("检查并修复异常数据").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                                }
                            }
                        }
                    } header: {
                        Text("数据管理").foregroundStyle(DesignSystem.textSecondary)
                    } footer: {
                        Text("卸载 App 会删除所有本地数据，建议定期导出备份")
                            .font(.caption2).foregroundStyle(DesignSystem.warningColor)
                    }
                    .listRowBackground(DesignSystem.cardBackground)

                    // 关于
                    Section {
                        HStack {
                            Text("版本").foregroundStyle(DesignSystem.textPrimary)
                            Spacer()
                            Text(appVersionText).foregroundStyle(DesignSystem.textTertiary)
                        }
                        HStack {
                            Text("开发者").foregroundStyle(DesignSystem.textPrimary)
                            Spacer()
                            Text("Yessi").foregroundStyle(DesignSystem.textTertiary)
                        }
                        if let url = URL(string: "https://github.com/Yessi-cmd/flashcount") {
                            Link(destination: url) {
                                HStack {
                                    Text("GitHub 仓库").foregroundStyle(DesignSystem.textPrimary)
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square").foregroundStyle(DesignSystem.textTertiary)
                                }
                            }
                        }
                    } header: {
                        Text("关于").foregroundStyle(DesignSystem.textSecondary)
                    }
                    .listRowBackground(DesignSystem.cardBackground)
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
            .sheet(isPresented: $showOnboarding) {
                OnboardingView(isPresented: $showOnboarding)
            }
            .sheet(isPresented: $showRecurringRules) {
                NavigationStack {
                    RecurringRulesView()
                }
            }
            .sheet(isPresented: $showTemplates) {
                TemplateManagementView()
            }
            .sheet(isPresented: $showCategoryManagement) {
                CategoryManagementView()
            }
            .sheet(isPresented: $showReminders) {
                ReminderView {
                    showReminders = false
                }
            }
            .sheet(isPresented: $showExportShare) {
                if let url = exportFileURL {
                    ShareSheet(items: [url])
                }
            }
            .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.json]) { result in
                previewImport(result: result)
            }
            .fileImporter(isPresented: $showCSVImportPicker, allowedContentTypes: [.commaSeparatedText]) { result in
                importCSV(result: result)
            }
            .confirmationDialog("导入备份", isPresented: Binding(
                get: { pendingImportURL != nil },
                set: { if !$0 { pendingImportURL = nil; importPreview = nil } }
            ), titleVisibility: .visible) {
                Button("合并导入") { performPendingImport(mode: .merge) }
                Button("替换全部本地数据", role: .destructive) { performPendingImport(mode: .replace) }
                Button("取消", role: .cancel) {}
            } message: {
                Text("\(importPreview?.summary ?? "")。合并保留本地数据；替换会删除当前所有本地数据。")
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

    private func exportCSV() {
        do {
            exportFileURL = try CSVTransactionService(modelContext: modelContext).exportToFile()
            showExportShare = true
        } catch {
            importResult = "CSV 导出失败：\(error.localizedDescription)"; showImportResult = true
        }
    }

    private func importCSV(result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            importResult = "CSV 文件选择失败"; showImportResult = true; return
        }
        guard url.startAccessingSecurityScopedResource() else {
            importResult = "无法访问 CSV 文件"; showImportResult = true; return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let count = try CSVTransactionService(modelContext: modelContext).importCSV(from: url)
            importResult = "已导入 \(count) 笔账单"; showImportResult = true
        } catch {
            importResult = "CSV 导入失败：\(error.localizedDescription)"; showImportResult = true
        }
    }

    private func previewImport(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                importResult = "无法访问文件"
                showImportResult = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                importPreview = try DataBackupService(modelContext: modelContext).previewJSON(from: url)
                pendingImportURL = url
            } catch {
                importResult = "备份读取失败：\(error.localizedDescription)"
                showImportResult = true
            }
        case .failure(let error):
            importResult = "文件选择失败：\(error.localizedDescription)"
            showImportResult = true
        }
    }

    private func performPendingImport(mode: DataBackupService.ImportMode) {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil
        importPreview = nil
        guard url.startAccessingSecurityScopedResource() else {
            importResult = "无法访问文件"; showImportResult = true; return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let report = try DataBackupService(modelContext: modelContext).importJSON(from: url, mode: mode)
            importResult = report.summary
            showImportResult = true
            HapticManager.success()
        } catch {
            importResult = "导入失败：\(error.localizedDescription)"
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
