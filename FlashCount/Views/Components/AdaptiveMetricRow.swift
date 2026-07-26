import SwiftUI

private struct MetricRowIsHorizontalKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// 由 `AdaptiveMetricRow` 写入，供分隔线和指标本身判断当前是横排还是纵排。
    var metricRowIsHorizontal: Bool {
        get { self[MetricRowIsHorizontalKey.self] }
        set { self[MetricRowIsHorizontalKey.self] = newValue }
    }
}

/// 并排指标的自适应容器。
///
/// 资产页那些「已存 / 目标 / 还差」三联指标原先是固定横排 + `minimumScaleFactor(0.72)`：
/// 辅助功能字号下金额被压到看不清，而不是换行。
///
/// 这里刻意用 `dynamicTypeSize` 判断，而不是 `ViewThatFits`：格子都带
/// `maxWidth: .infinity`（等宽分栏要靠它），这种可伸缩的候选视图对任何提议宽度
/// 都回答「放得下」，`ViewThatFits` 会永远选中第一个候选，等于没做适配。
struct AdaptiveMetricRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var isHorizontal: Bool {
        !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        Group {
            if isHorizontal {
                HStack(spacing: 0) { content }
            } else {
                VStack(alignment: .leading, spacing: 12) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .environment(\.metricRowIsHorizontal, isHorizontal)
    }
}

/// 竖直分隔线只在横排时有意义，纵排时跟着布局一起消失。
struct AdaptiveMetricDivider: View {
    @Environment(\.metricRowIsHorizontal) private var isHorizontal

    let height: CGFloat

    init(height: CGFloat = 32) {
        self.height = height
    }

    var body: some View {
        if isHorizontal {
            Rectangle()
                .fill(DesignSystem.dividerColor)
                .frame(width: 1, height: height)
        }
    }
}

/// 单个指标格。横排时是「标题在上、数字在下」的窄栏；纵排时改成
/// 「标题在左、数字在右」的一行——纵向列表里居中排版会读不出对应关系。
struct AdaptiveMetric: View {
    @Environment(\.metricRowIsHorizontal) private var isHorizontal

    let title: String
    let value: String
    let color: Color

    var body: some View {
        if isHorizontal {
            VStack(spacing: 3) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.textTertiary)
                Text(value)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(DesignSystem.textSecondary)
                Spacer(minLength: 8)
                Text(value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
                    .multilineTextAlignment(.trailing)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
