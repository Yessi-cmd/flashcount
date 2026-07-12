import SwiftUI

struct QuickEntryNumberPad: View {
    let onKeyPress: (String) -> Void

    private let buttons = [
        ["7", "8", "9", "⌫"],
        ["4", "5", "6", "收入"],
        ["1", "2", "3", "支出"],
        [".", "0", "00", ""]
    ]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(buttons, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { button in
                        if button.isEmpty {
                            Color.clear.frame(height: 42)
                        } else {
                            Button { onKeyPress(button) } label: {
                                Text(button)
                                    .font(button == "收入" || button == "支出" ? .caption2.weight(.semibold) : .body.weight(.medium))
                                    .frame(maxWidth: .infinity).frame(height: 42)
                                    .background(background(for: button))
                                    .foregroundStyle(foreground(for: button))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay {
                                        if button == "收入" || button == "支出" {
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(button == "收入" ? DesignSystem.incomeColor.opacity(0.3) : DesignSystem.expenseColor.opacity(0.3))
                                        }
                                    }
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                    }
                }
            }
        }
    }

    private func background(for button: String) -> Color {
        if button == "收入" { return DesignSystem.incomeColor.opacity(0.12) }
        if button == "支出" { return DesignSystem.expenseColor.opacity(0.12) }
        return DesignSystem.softFill
    }

    private func foreground(for button: String) -> Color {
        if button == "⌫" { return DesignSystem.textSecondary }
        if button == "收入" { return DesignSystem.incomeColor }
        if button == "支出" { return DesignSystem.expenseColor }
        return DesignSystem.textPrimary
    }
}

struct QuickEntrySubmitButton: View {
    let isEnabled: Bool
    let isExpense: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("保存")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(
                    isEnabled
                        ? (isExpense ? AnyShapeStyle(DesignSystem.expenseGradient) : AnyShapeStyle(DesignSystem.incomeGradient))
                        : AnyShapeStyle(.gray.opacity(0.3))
                )
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
        }
        .disabled(!isEnabled)
        .buttonStyle(PressableButtonStyle())
    }
}
