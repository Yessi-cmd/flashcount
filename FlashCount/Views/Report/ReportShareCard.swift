import SwiftUI

/// 分享用的报表卡片。
/// 刻意不读环境对象：`ImageRenderer` 脱离视图层级渲染，一切都必须显式传入。
struct ReportShareCard: View {
    let periodTitle: String
    let rangeTitle: String
    let totalExpense: Decimal
    /// 收入与结余仅在隐私锁已解锁时传入；锁定时为 nil，卡片整块不出现。
    let income: (total: Decimal, net: Decimal)?
    let topCategories: [CategorySpending]
    let streakDays: Int

    static let width: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("FlashCount", systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.primaryColor)
                Spacer()
                Text(periodTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DesignSystem.textSecondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(rangeTitle)
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textTertiary)
                Text(totalExpense.formattedCurrency)
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(DesignSystem.textPrimary)
                Text("总支出")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textSecondary)
            }

            if let income {
                HStack(spacing: 10) {
                    shareMetric(title: "收入", value: income.total.formattedCurrency, color: DesignSystem.incomeColor)
                    shareMetric(
                        title: "结余",
                        value: income.net.formattedCurrency,
                        color: income.net >= 0 ? DesignSystem.incomeColor : DesignSystem.expenseColor
                    )
                }
            }

            if !topCategories.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("主要去向")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignSystem.textSecondary)
                    ForEach(topCategories.prefix(3)) { item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: item.categoryColor))
                                .frame(width: 7, height: 7)
                            Text(item.categoryName)
                                .font(.caption)
                                .foregroundStyle(DesignSystem.textPrimary)
                            Spacer()
                            Text(item.amount.formattedCurrency)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(DesignSystem.textSecondary)
                            Text(ReportPercentageFormatter.categoryShare(item.percentage))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(DesignSystem.textTertiary)
                        }
                    }
                }
            }

            HStack {
                Label("连续记账 \(streakDays) 天", systemImage: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.primaryColor)
                Spacer()
                Text("本地记账 · 数据不出设备")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.textTertiary)
            }
        }
        .padding(20)
        .frame(width: Self.width, alignment: .leading)
        .background(DesignSystem.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(DesignSystem.borderColor, lineWidth: 1)
        )
        .padding(12)
        .background(DesignSystem.surfaceBackground)
    }

    private func shareMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(DesignSystem.textTertiary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(DesignSystem.softFill)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// 系统分享面板。图片在本机渲染，不经过任何网络。
struct ReportShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// 渲染好的报表分享图，用于交给系统分享面板。
struct ReportShareImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
