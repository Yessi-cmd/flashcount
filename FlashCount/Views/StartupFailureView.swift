import SwiftUI

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
