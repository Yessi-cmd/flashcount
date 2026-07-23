import SwiftUI

struct QuickEntryNumberPad: View {
    let onKeyPress: (String) -> Void

    private let legacyKeyHeight: CGFloat = 42
    private let liquidGlassLabelHeight: CGFloat = 32

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
                            Color.clear.frame(height: legacyKeyHeight)
                        } else {
                            keyButton(for: button)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keyButton(for button: String) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            liquidGlassKeyButton(for: button)
        } else {
            legacyKeyButton(for: button)
        }
#else
        legacyKeyButton(for: button)
#endif
    }

#if compiler(>=6.2)
    @available(iOS 26.0, *)
    private func liquidGlassKeyButton(for button: String) -> some View {
        Button { onKeyPress(button) } label: {
            baseKeyLabel(for: button, height: liquidGlassLabelHeight)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .tint(glassButtonTint(for: button))
        .accessibilityIdentifier("quickEntry.key.\(button)")
    }
#endif

    private func legacyKeyButton(for button: String) -> some View {
        Button { onKeyPress(button) } label: {
            baseKeyLabel(for: button, height: legacyKeyHeight)
                .background(background(for: button))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if button == "收入" || button == "支出" {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                button == "收入"
                                    ? DesignSystem.incomeColor.opacity(0.3)
                                    : DesignSystem.expenseColor.opacity(0.3)
                            )
                    }
                }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("quickEntry.key.\(button)")
    }

    private func baseKeyLabel(for button: String, height: CGFloat) -> some View {
        Text(button)
            .font(
                button == "收入" || button == "支出"
                    ? DesignSystem.Typography.supportingLabel
                    : DesignSystem.Typography.keypadDigit
            )
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .foregroundStyle(foreground(for: button))
    }

    private func glassButtonTint(for button: String) -> Color {
        if button == "收入" { return DesignSystem.incomeColor.opacity(0.20) }
        if button == "支出" { return DesignSystem.expenseColor.opacity(0.20) }
        return DesignSystem.cardBackground.opacity(0.16)
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

    @ViewBuilder
    var body: some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            liquidGlassButton
        } else {
            legacyButton
        }
#else
        legacyButton
#endif
    }

#if compiler(>=6.2)
    @available(iOS 26.0, *)
    private var liquidGlassButton: some View {
        Button(action: action) {
            Text("保存")
                .font(DesignSystem.Typography.controlLabel)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
        }
        .buttonStyle(.glassProminent)
        .tint(isExpense ? DesignSystem.expenseColor : DesignSystem.incomeColor)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .animation(DesignSystem.quickAnimation, value: isEnabled)
        .accessibilityIdentifier("quickEntry.save")
    }
#endif

    private var legacyButton: some View {
        Button(action: action) {
            Text("保存")
                .font(DesignSystem.Typography.controlLabel).foregroundStyle(.white)
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
        .accessibilityIdentifier("quickEntry.save")
    }
}
