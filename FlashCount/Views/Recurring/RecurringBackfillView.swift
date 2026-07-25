import SwiftUI

/// 让用户在真实交易写入前确认逾期的周期发生项。
struct RecurringBackfillView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var privacyLock: PrivacyLockService

    let previews: [RecurringOccurrencePreview]

    @State private var skippedKeys: Set<String> = []
    @State private var isSaving = false
    @State private var saveError: String?

    private var selectedPreviews: [RecurringOccurrencePreview] {
        previews.filter { !skippedKeys.contains($0.id) }
    }

    private var selectedCashDelta: Decimal {
        selectedPreviews.reduce(Decimal.zero) { $0 + $1.signedAmount }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.sectionSpacing) {
                        explanationCard
                        summaryCard
                        occurrenceList
                    }
                    .padding()
                }
            }
            .navigationTitle("周期补账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消", action: dismiss.callAsFunction)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "保存中…" : "确认补账", action: resolve)
                        .disabled(isSaving || previews.isEmpty)
                }
            }
            .alert("补账失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好的", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("确认后才会写入账本", systemImage: "checkmark.shield.fill")
                .font(.headline)
                .foregroundStyle(DesignSystem.textPrimary)
            Text("这些记录来自已经到期但尚未处理的周期规则。跳过的项目不会改变资金池，也不会再次出现在本次补账列表中。")
                .font(.subheadline)
                .foregroundStyle(DesignSystem.textSecondary)
        }
        .glassCard()
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("本次处理")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
                Spacer()
                Text("\(selectedPreviews.count)/\(previews.count) 笔")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(DesignSystem.primaryColor)
            }

            HStack(spacing: 10) {
                Button("全部补账", systemImage: "checkmark.circle", action: selectAll)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.primaryColor)

                Button("全部跳过", systemImage: "forward.end", action: skipAll)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(DesignSystem.textSecondary)

                Spacer()
            }

            HStack {
                Text("预计现金变化")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textSecondary)
                Spacer()
                Text(privacyLock.isUnlocked ? selectedCashDelta.formattedCurrency : privacyLock.maskedText)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(selectedCashDelta >= 0 ? DesignSystem.incomeColor : DesignSystem.expenseColor)
            }
        }
        .glassCard()
    }

    private var occurrenceList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("待处理项目")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.textSecondary)

            ForEach(previews) { preview in
                RecurringBackfillRow(
                    preview: preview,
                    isSkipped: skippedKeys.contains(preview.id),
                    isUnlocked: privacyLock.isUnlocked,
                    maskedText: privacyLock.maskedText,
                    onToggle: { toggle(preview) }
                )
            }
        }
    }

    private func toggle(_ preview: RecurringOccurrencePreview) {
        if skippedKeys.contains(preview.id) {
            skippedKeys.remove(preview.id)
        } else {
            skippedKeys.insert(preview.id)
        }
    }

    private func selectAll() {
        skippedKeys.removeAll()
    }

    private func skipAll() {
        skippedKeys = Set(previews.map(\.id))
    }

    private func resolve() {
        guard !isSaving else { return }
        isSaving = true
        let selections = previews.map { preview in
            RecurringBackfillSelection(
                occurrenceKey: preview.id,
                action: skippedKeys.contains(preview.id) ? .skip : .generate
            )
        }

        do {
            _ = try RecurringOccurrenceService(modelContext: modelContext).resolve(selections)
            HapticManager.success()
            dismiss()
        } catch {
            isSaving = false
            saveError = error.localizedDescription
            HapticManager.error()
        }
    }
}

private struct RecurringBackfillRow: View {
    let preview: RecurringOccurrencePreview
    let isSkipped: Bool
    let isUnlocked: Bool
    let maskedText: String
    let onToggle: () -> Void

    private var hidesIncome: Bool {
        PrivacyVisibilityPolicy.hidesIncome(
            isExpense: preview.isExpense,
            isUnlocked: isUnlocked
        )
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: isSkipped ? "circle" : "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(isSkipped ? DesignSystem.textTertiary : DesignSystem.primaryColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(hidesIncome ? "隐私收入" : preview.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.textPrimary)
                    Text("\(preview.scheduledDate.shortDateString) · \(isSkipped ? "本次跳过" : "准备补账")")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textTertiary)
                }

                Spacer(minLength: 8)

                Text(hidesIncome ? maskedText : preview.amount.formattedCurrency)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(preview.isExpense ? DesignSystem.expenseColor : DesignSystem.incomeColor)
                    .privacySensitive(hidesIncome)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(DesignSystem.cardPadding)
        .background(isSkipped ? DesignSystem.softFill.opacity(0.55) : DesignSystem.cardBackground)
        .clipShape(.rect(cornerRadius: DesignSystem.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .stroke(DesignSystem.borderColor, lineWidth: 1)
        }
    }
}
