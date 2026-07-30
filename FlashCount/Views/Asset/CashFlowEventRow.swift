import SwiftUI

struct CashFlowEventRow: View {
    let event: CashFlowEvent
    let hidesMoney: Bool
    let maskedText: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 30, height: 30)
                .background(iconColor.opacity(0.12))
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(event.isProtectedIncome ? "隐私收入" : event.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.textPrimary)
                Text("\(event.date.shortDateString) · \(event.source.title)")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textTertiary)
            }

            Spacer(minLength: 8)

            Text(
                hidesMoney || event.isProtectedIncome
                    ? maskedText
                    : event.signedAmount.formattedCurrency
            )
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(
                event.signedAmount >= 0
                    ? DesignSystem.incomeColor
                    : DesignSystem.expenseColor
            )
            .privacySensitive(hidesMoney || event.isProtectedIncome)
        }
        .padding(DesignSystem.cardPadding)
        .background(DesignSystem.cardBackground)
        .clipShape(.rect(cornerRadius: DesignSystem.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .stroke(DesignSystem.borderColor, lineWidth: 1)
        }
    }

    private var iconName: String {
        switch event.source {
        case .recurring:
            return "repeat.circle.fill"
        case .installment:
            return "creditcard.trianglebadge.exclamationmark.fill"
        case .routine:
            return "chart.line.uptrend.xyaxis"
        }
    }

    private var iconColor: Color {
        event.signedAmount >= 0
            ? DesignSystem.incomeColor
            : DesignSystem.expenseColor
    }
}
