import SwiftUI

/// 表单校验提示。消息为空时不占位——校验信息出现和消失都不该让布局跳动。
struct ValidationMessage: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(DesignSystem.dangerColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(message)
        }
    }
}
