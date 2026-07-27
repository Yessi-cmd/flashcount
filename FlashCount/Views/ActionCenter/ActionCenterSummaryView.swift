import SwiftUI

/// 行动中心顶部的总览。
struct ActionCenterSummaryView: View {
    let snapshot: LocalActionCenterSnapshot

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: snapshot.isEmpty ? "checkmark.circle.fill" : "bolt.badge.clock.fill")
                .font(.title2)
                .foregroundStyle(snapshot.isEmpty ? DesignSystem.incomeColor : DesignSystem.warningColor)
                .frame(width: 46, height: 46)
                .background(
                    (snapshot.isEmpty ? DesignSystem.incomeColor : DesignSystem.warningColor)
                        .opacity(0.12)
                )
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.isEmpty ? "目前没有需要处理的事项" : "本地行动待处理")
                    .font(.headline)
                    .foregroundStyle(DesignSystem.textPrimary)
                Text(snapshot.isEmpty ? "预算、扣款、分期、建议和提醒都已整理完成" : "需要处理 \(snapshot.totalCount) 项，按优先级排列")
                    .font(.subheadline)
                    .foregroundStyle(DesignSystem.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .heroCard(
            accent: snapshot.isEmpty ? DesignSystem.incomeColor : DesignSystem.warningColor
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(snapshot.isEmpty ? "目前没有需要处理的事项" : "本地行动待处理")
        .accessibilityValue(snapshot.isEmpty ? "暂无事项" : "共 \(snapshot.totalCount) 项")
    }
}
