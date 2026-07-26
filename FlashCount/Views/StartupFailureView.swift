import SwiftUI

/// 启动失败时的兜底页面。必须明确告知数据未被删除或覆盖，并提供重试入口。
struct StartupFailureView: View {
    let title: String
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button("重试", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .tint(DesignSystem.primaryColor)
    }
}
