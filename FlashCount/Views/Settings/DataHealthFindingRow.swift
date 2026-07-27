import SwiftUI

/// 一条体检结论。可自动修复与需人工处理的数量分开显示。
struct DataHealthFindingRow: View {
    let finding: DataHealthFinding

    var body: some View {
        HStack(spacing: DesignSystem.space12) {
            Image(systemName: finding.kind.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(finding.kind.accent)
                .frame(width: 28, height: 28)
                .background(finding.kind.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(finding.kind.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.textPrimary)
                Text(finding.detail)
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: DesignSystem.space8)

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(finding.count)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(finding.count == 0 ? DesignSystem.textTertiary : finding.kind.accent)
                Text(finding.statusText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(finding.count == 0 ? DesignSystem.textTertiary : finding.kind.accent)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("发现 \(finding.count) 项，\(finding.statusText)")
        }
        .padding(.vertical, DesignSystem.space8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(finding.kind.title)，发现 \(finding.count) 项，\(finding.statusText)。\(finding.detail)")
    }
}
