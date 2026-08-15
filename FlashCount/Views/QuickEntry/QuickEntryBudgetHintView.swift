import SwiftUI

/// 快速记账金额下方的实时预算条。
///
/// 没有设置总预算或正在记收入时不显示；输入金额后按「记完这笔」的
/// 口径重算，所以颜色会在你打字时直接变化。
struct QuickEntryBudgetHintView: View {
    let hint: QuickEntryBudgetHint

    private var level: BudgetAlertLevel { hint.level }

    private var accent: Color {
        switch level {
        case .healthy: return DesignSystem.primaryColor
        case .warning: return DesignSystem.warningColor
        case .danger: return DesignSystem.dangerColor
        }
    }

    private var iconName: String {
        switch level {
        case .healthy: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "flame.fill"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.caption2.weight(.semibold))
            Text(hint.text)
                .font(DesignSystem.Typography.supportingLabel)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(accent.opacity(0.10))
        .clipShape(Capsule())
        .animation(DesignSystem.quickAnimation, value: hint.text)
        .animation(DesignSystem.quickAnimation, value: level)
        .accessibilityIdentifier("quickEntry.budgetHint")
    }
}
