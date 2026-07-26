import SwiftUI
import SwiftData

/// 记完一笔后的确认条：说清记了什么、必要时带上预算提醒，并留一个撤销入口。
///
/// 不放「再记一笔」——提示条正好浮在底栏那颗「记一笔」按钮上方，重复一个入口
/// 只会挤掉撤销的位置。
struct QuickEntrySavedToast: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var feedback: QuickEntryFeedbackCenter

    let entry: QuickEntryFeedbackCenter.SavedEntry

    @State private var undoError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(DesignSystem.incomeColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.headline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.textPrimary)
                        .monospacedDigit()
                    Text(entry.detail)
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    undo()
                } label: {
                    Text("撤销")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.primaryColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("quickEntry.undoSaved")

                Button {
                    feedback.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(DesignSystem.textTertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("收起提示")
            }

            if let reminder = entry.budgetReminder {
                HStack(spacing: 6) {
                    Image(systemName: reminderIcon)
                    Text(reminder)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(reminderColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(reminderColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DesignSystem.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignSystem.borderColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quickEntry.savedToast")
        .saveErrorAlert($undoError)
    }

    private var reminderIcon: String {
        switch entry.budgetAlertLevel {
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "flame.fill"
        default: return "checkmark.circle.fill"
        }
    }

    private var reminderColor: Color {
        switch entry.budgetAlertLevel {
        case .warning: return DesignSystem.warningColor
        case .danger: return DesignSystem.dangerColor
        default: return DesignSystem.incomeColor
        }
    }

    /// 撤销一次「新增」就是把它删掉。取模型时同时挡掉已被别处删除的情况，
    /// 否则撤销会对着一个失效对象报错。
    private func undo() {
        guard let transaction = modelContext.model(for: entry.transactionID) as? Transaction,
              !transaction.isDeleted else {
            feedback.dismiss()
            return
        }

        do {
            _ = try TransactionMutationService(modelContext: modelContext).delete(transaction)
            HapticManager.success()
            feedback.dismiss()
        } catch {
            undoError = error.localizedDescription
            HapticManager.error()
        }
    }
}
