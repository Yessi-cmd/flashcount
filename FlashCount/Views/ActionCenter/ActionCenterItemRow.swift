import SwiftUI

/// 行动中心里的一条待办。
struct ActionCenterItemRow: View {
    let item: LocalActionItem
    let hidesSensitiveAmounts: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: item.kind.iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 36, height: 36)
                    .background(accentColor.opacity(0.12))
                    .clipShape(.rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.textPrimary)
                        .lineLimit(1)

                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if let amount = item.amount {
                    Text(displayAmount(amount))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(amountColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .privacySensitive(hidesSensitiveAmounts && item.isPrivacySensitiveAmount)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.textTertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("actionCenter.item.\(item.kind.rawValue)")
    }

    private var accentColor: Color {
        switch item.kind {
        case .budgetOverrun:
            DesignSystem.dangerColor
        case .cashFlowRisk:
            item.severity == .urgent
                ? DesignSystem.dangerColor
                : DesignSystem.warningColor
        case .recurringDebit, .installmentDue:
            DesignSystem.expenseColor
        case .recurringSuggestion:
            DesignSystem.primaryColor
        case .incompleteReminder:
            DesignSystem.warningColor
        }
    }

    private var amountColor: Color {
        item.kind == .installmentDue ? DesignSystem.expenseColor : accentColor
    }

    private var accessibilityValue: String {
        if let amount = item.amount,
           !(hidesSensitiveAmounts && item.isPrivacySensitiveAmount)
        {
            return "\(item.detail)，\(amount.formattedCurrency)"
        }
        return item.detail
    }

    private func displayAmount(_ amount: Decimal) -> String {
        hidesSensitiveAmounts && item.isPrivacySensitiveAmount
            ? "****"
            : amount.formattedCurrency
    }
}
