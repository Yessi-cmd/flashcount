import SwiftUI

/// 修复前的预览：逐项列出将要执行的改动，确认后才写入。
struct DataHealthRepairPreviewView: View {
    let report: DataHealthReport
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmationPresented = false

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.sectionSpacing) {
                        previewHeader
                        repairActionsCard
                        manualIssuesCard
                    }
                    .padding()
                }
            }
            .navigationTitle("修复预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(DesignSystem.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("提交修复") {
                        isConfirmationPresented = true
                    }
                    .disabled(!report.hasRepairableIssues)
                    .foregroundStyle(report.hasRepairableIssues ? DesignSystem.primaryColor : DesignSystem.textTertiary)
                }
            }
            .confirmationDialog(
                "确认提交修复？",
                isPresented: $isConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("确认提交") {
                    dismiss()
                    onConfirm()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("本次会在同一个本地数据库事务中提交，失败时会自动回滚。")
            }
        }
    }

    private var previewHeader: some View {
        VStack(alignment: .leading, spacing: DesignSystem.space8) {
            Label("提交前不会修改数据", systemImage: "eye.fill")
                .font(.headline)
                .foregroundStyle(DesignSystem.primaryColor)

            Text("下面是本次扫描生成的修复计划。只有点击“提交修复”并确认后，才会写入本地数据。")
                .font(.subheadline)
                .foregroundStyle(DesignSystem.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .heroCard(accent: DesignSystem.primaryColor)
    }

    private var repairActionsCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.space12) {
            Text("将要执行")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.textSecondary)

            if report.plan.hasChanges {
                previewLine(
                    icon: "wrench.and.screwdriver.fill",
                    title: "安全修复项",
                    detail: "共 \(report.plan.actionCount) 个本地数据修复动作"
                )
                previewLine(
                    icon: "lock.shield.fill",
                    title: "提交方式",
                    detail: "一次保存，任意失败都会回滚"
                )
            } else {
                previewLine(
                    icon: "checkmark.circle.fill",
                    title: "没有可自动修复项",
                    detail: "当前问题需要人工确认或已经是正常状态"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder
    private var manualIssuesCard: some View {
        if report.manualIssueCount > 0 {
            VStack(alignment: .leading, spacing: DesignSystem.space12) {
                Label("需要人工确认", systemImage: "person.fill.questionmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.warningColor)

                ForEach(report.findings.filter { $0.manualCount > 0 }) { finding in
                    HStack(alignment: .top, spacing: DesignSystem.space8) {
                        Text("•")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(finding.kind.title)：\(finding.manualCount) 项")
                                .font(.subheadline)
                                .foregroundStyle(DesignSystem.textPrimary)
                            Text(finding.detail)
                                .font(.caption)
                                .foregroundStyle(DesignSystem.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .foregroundStyle(DesignSystem.warningColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    private func previewLine(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.space12) {
            Image(systemName: icon)
                .foregroundStyle(DesignSystem.primaryColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textTertiary)
            }
        }
    }
}
