import SwiftUI
import SwiftData

/// 本地数据健康中心：扫描、预览、执行修复。预览后数据若有变化必须重新扫描。
struct DataHealthCenterView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var report: DataHealthReport?
    @State private var isScanning = false
    @State private var isApplying = false
    @State private var isPreviewPresented = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DesignSystem.sectionSpacing) {
                        statusCard

                        if isScanning {
                            ProgressView("正在检查本地数据…")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DesignSystem.space24)
                        } else if let report {
                            findingsCard(report)
                            actionCard(report)
                        } else {
                            emptyState
                        }
                    }
                    .padding()
                }
                .refreshable {
                    scan()
                }
            }
            .navigationTitle("本地数据健康中心")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(DesignSystem.primaryColor)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("重新扫描", systemImage: "arrow.clockwise", action: scan)
                        .labelStyle(.iconOnly)
                        .disabled(isScanning || isApplying)
                        .accessibilityLabel("重新扫描本地数据")
                }
            }
            .sheet(isPresented: $isPreviewPresented) {
                if let report {
                    DataHealthRepairPreviewView(report: report) {
                        apply(report)
                    }
                }
            }
            .alert("数据健康中心", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("修复完成", isPresented: Binding(
                get: { successMessage != nil },
                set: { if !$0 { successMessage = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(successMessage ?? "")
            }
            .task {
                scan()
            }
        }
    }

    private var statusCard: some View {
        let isHealthy = report?.isHealthy == true
        let accent = report == nil ? DesignSystem.primaryColor : (isHealthy ? DesignSystem.incomeColor : DesignSystem.warningColor)

        return VStack(alignment: .leading, spacing: DesignSystem.space12) {
            Label(
                report == nil ? "本地数据" : (isHealthy ? "数据状态良好" : "发现需要关注的数据"),
                systemImage: report == nil ? "heart.text.square.fill" : (isHealthy ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
            )
            .font(.title3.weight(.semibold))
            .foregroundStyle(accent)

            if let report {
                Text("上次扫描：\(report.scannedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textTertiary)
                Text(
                    report.isHealthy
                        ? "没有发现需要修复的本地数据。"
                        : "已发现 \(report.totalIssueCount) 项问题，其中 \(report.plan.actionCount) 项可以安全修复。"
                )
                .font(.subheadline)
                .foregroundStyle(DesignSystem.textSecondary)
            } else {
                Text("点击后会在设备本地只读检查账本、预算和资金池数据。")
                    .font(.subheadline)
                    .foregroundStyle(DesignSystem.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .heroCard(accent: accent)
    }

    private func findingsCard(_ report: DataHealthReport) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.space8) {
            Text("检查结果")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.textSecondary)

            ForEach(report.findings) { finding in
                DataHealthFindingRow(finding: finding)
                if finding.id != report.findings.last?.id {
                    Divider().background(DesignSystem.dividerColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func actionCard(_ report: DataHealthReport) -> some View {
        VStack(spacing: DesignSystem.space12) {
            if report.hasRepairableIssues {
                Button {
                    isPreviewPresented = true
                } label: {
                    Label("查看修复预览", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.primaryColor)
                .accessibilityIdentifier("dataHealth.preview")
            }

            Button("重新扫描", systemImage: "arrow.clockwise", action: scan)
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
                .disabled(isScanning || isApplying)
                .accessibilityIdentifier("dataHealth.rescan")

            Text("扫描不会上传数据；只有确认修复后才会写入本地数据库。")
                .font(.caption2)
                .foregroundStyle(DesignSystem.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private var emptyState: some View {
        VStack(spacing: DesignSystem.space12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 34))
                .foregroundStyle(DesignSystem.primaryColor)
                .accessibilityHidden(true)
            Text("准备检查本地数据")
                .font(.headline)
                .foregroundStyle(DesignSystem.textPrimary)
            Text("扫描只读，不会自动修改任何记录。")
                .font(.subheadline)
                .foregroundStyle(DesignSystem.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.space24)
        .glassCard()
    }

    private func scan() {
        guard !isScanning, !isApplying else { return }
        isScanning = true
        errorMessage = nil

        do {
            report = try DataHealthService(modelContext: modelContext).scan()
        } catch {
            errorMessage = "本地数据扫描失败：\(error.localizedDescription)"
        }

        isScanning = false
    }

    private func apply(_ previewReport: DataHealthReport) {
        guard !isApplying else { return }
        isApplying = true
        errorMessage = nil

        do {
            let result = try DataHealthService(modelContext: modelContext).apply(previewReport.plan)
            report = try DataHealthService(modelContext: modelContext).scan()
            let remaining = result.remainingManualIssueCount
            successMessage = remaining > 0
                ? "已原子提交 \(result.actionCount) 项修复，仍有 \(remaining) 项需要人工确认。"
                : "已原子提交 \(result.actionCount) 项修复，重新扫描后未发现剩余问题。"
            HapticManager.success()
        } catch {
            errorMessage = "修复未提交：\(error.localizedDescription)"
            HapticManager.error()
        }

        isApplying = false
    }
}
