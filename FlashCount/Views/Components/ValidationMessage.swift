import SwiftUI

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
