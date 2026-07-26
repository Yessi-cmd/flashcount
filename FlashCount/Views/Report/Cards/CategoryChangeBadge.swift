import SwiftUI

/// 分类环比徽标。
/// 每个分类的 `changeFromLastPeriod` 一直都在算，之前却只喂给一条洞察文案，
/// 排行和图例里看不见——这里把它直接标在数字旁边。
struct CategoryChangeBadge: View {
    let category: CategorySpending

    var body: some View {
        if category.isAggregate {
            // 「其他」是长尾合并出来的，没有可比的上期口径。
            EmptyView()
        } else if let change = category.changeFromLastPeriod {
            let presentation = ReportChangePresentation.make(change: change, metric: .expense)
            if presentation.direction != .unchanged {
                label(
                    icon: presentation.direction == .increase ? "arrow.up.right" : "arrow.down.right",
                    text: presentation.text,
                    color: presentation.isFavorable == true ? DesignSystem.incomeColor : DesignSystem.expenseColor,
                    accessibility: "较上期\(presentation.direction == .increase ? "增加" : "减少") \(presentation.text)"
                )
            }
        } else if category.amount > 0 {
            // 上期该分类没有支出，环比无从计算——直接说明是新增的。
            label(
                icon: "sparkle",
                text: "新增",
                color: DesignSystem.warningColor,
                accessibility: "上期没有这一分类的支出"
            )
        }
    }

    private func label(icon: String, text: String, color: Color, accessibility: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.caption2.weight(.medium).monospacedDigit())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityLabel(accessibility)
    }
}
