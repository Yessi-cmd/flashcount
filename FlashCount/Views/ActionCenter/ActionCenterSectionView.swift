import SwiftUI

/// 行动中心里同类待办的一组。
struct ActionCenterSectionView: View {
    let section: LocalActionSection
    let hidesSensitiveAmounts: Bool
    let onSelect: (LocalActionItem) -> Void
    let onShowAll: (LocalActionDestination) -> Void

    private let visibleItemLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(section.title, systemImage: section.kind.iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
                    .accessibilityIdentifier("actionCenter.section.\(section.kind.rawValue)")

                Spacer(minLength: 8)

                Text("\(section.items.count) 项")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(DesignSystem.textTertiary)
            }

            ForEach(section.items.prefix(visibleItemLimit)) { item in
                ActionCenterItemRow(
                    item: item,
                    hidesSensitiveAmounts: hidesSensitiveAmounts,
                    onTap: { onSelect(item) }
                )

                if item.id != section.items.prefix(visibleItemLimit).last?.id {
                    Divider()
                        .background(DesignSystem.dividerColor)
                }
            }

            if section.items.count > visibleItemLimit,
               let destination = section.items.first?.destination
            {
                Button("查看全部（\(section.items.count) 项）") {
                    onShowAll(destination)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DesignSystem.primaryColor)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("actionCenter.more.\(section.kind.rawValue)")
            }
        }
        .glassCard()
    }
}
