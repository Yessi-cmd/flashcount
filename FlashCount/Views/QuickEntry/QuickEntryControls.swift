import SwiftUI

/// 记账页的自定义数字键盘。键位含义与「+」累加见 `QuickEntryAmountInput`。
struct QuickEntryNumberPad: View {
    let onKeyPress: (String) -> Void

    private let legacyKeyHeight: CGFloat = 44
    // 玻璃按钮自带上下内边距，38pt 标签的整键仍 ≥44pt 点按目标；
    // 压缩键盘高度，把屏幕比例还给上方表单区。
    private let liquidGlassLabelHeight: CGFloat = 38

    // 右下角原本是个空键位，白占 1/16 的键盘面积。
    // 「+」把拆账、凑总额这个记账里最常见的算术补上了。
    private let buttons = [
        ["7", "8", "9", "⌫"],
        ["4", "5", "6", "收入"],
        ["1", "2", "3", "支出"],
        [".", "0", "00", "+"]
    ]

    var body: some View {
        VStack(spacing: 5) {
            ForEach(buttons, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { button in
                        keyButton(for: button)
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
        .accessibilityLabel(Self.accessibilityLabel(for: button))
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
        .accessibilityLabel(Self.accessibilityLabel(for: button))
        .accessibilityIdentifier("quickEntry.key.\(button)")
    }

    private static func accessibilityLabel(for button: String) -> String {
        switch button {
        case "⌫": return "删除最后一位"
        case "+": return "累加当前金额，继续输入下一笔"
        default: return button
        }
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
        if button == "+" { return DesignSystem.primaryColor.opacity(0.18) }
        return DesignSystem.cardBackground.opacity(0.16)
    }

    private func background(for button: String) -> Color {
        if button == "收入" { return DesignSystem.incomeColor.opacity(0.12) }
        if button == "支出" { return DesignSystem.expenseColor.opacity(0.12) }
        if button == "+" { return DesignSystem.primaryColor.opacity(0.10) }
        return DesignSystem.softFill
    }

    private func foreground(for button: String) -> Color {
        if button == "⌫" { return DesignSystem.textSecondary }
        if button == "收入" { return DesignSystem.incomeColor }
        if button == "支出" { return DesignSystem.expenseColor }
        if button == "+" { return DesignSystem.primaryColor }
        return DesignSystem.textPrimary
    }
}

/// 记账页的保存按钮，颜色跟随收支类型。
struct QuickEntrySubmitButton: View {
    let isEnabled: Bool
    let isExpense: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .frame(minHeight: 40)
        }
        .buttonStyle(.glassProminent)
        .tint(isExpense ? DesignSystem.expenseColor : DesignSystem.incomeColor)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .animation(reduceMotion ? nil : DesignSystem.quickAnimation, value: isEnabled)
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
