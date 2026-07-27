import SwiftUI

/// 单件实物资产的卡片：估值、折旧与日均成本。
struct PhysicalAssetCard: View {
    let asset: PhysicalAsset
    let hidesMoney: Bool
    let maskedText: String

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(DesignSystem.primaryColor.opacity(0.15)).frame(width: 40, height: 40)
                    Image(systemName: asset.category.icon).font(.subheadline).foregroundStyle(DesignSystem.primaryColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.name).font(.subheadline.weight(.medium)).foregroundStyle(DesignSystem.textPrimary)
                    Text("\(asset.category.rawValue) · 持有 \(asset.daysHeld()) 天").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("估值 \(hidesMoney ? maskedText : asset.currentValue().formattedCurrency)")
                        .font(.caption.monospacedDigit()).foregroundStyle(DesignSystem.textSecondary)
                    Text("日均 \(hidesMoney ? maskedText : asset.dailyCost().formattedCurrency)")
                        .font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(DesignSystem.primaryColor)
                }
            }
            progress
        }
        .padding().background(DesignSystem.softFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius).stroke(DesignSystem.borderColor))
    }

    @ViewBuilder private var progress: some View {
        if asset.targetDailyCost > 0 {
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(DesignSystem.softFill).frame(height: 6)
                        RoundedRectangle(cornerRadius: 3).fill(progressColor)
                            .frame(width: hidesMoney ? 0 : geo.size.width * asset.progressToTarget(), height: 6)
                    }
                }
                .frame(height: 6)
                HStack {
                    Text(hidesMoney ? maskedText : "\(Int(asset.progressToTarget() * 100))%")
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(hidesMoney ? DesignSystem.textTertiary : progressColor)
                    Spacer()
                    progressDetail
                }
            }
        } else {
            HStack { Text("未设置目标日成本").font(.caption2).foregroundStyle(DesignSystem.textTertiary); Spacer() }
        }
    }

    @ViewBuilder private var progressDetail: some View {
        if hidesMoney {
            Text("验证后显示目标进度").font(.caption2).foregroundStyle(DesignSystem.textTertiary)
        } else if let remaining = asset.daysToTarget(), remaining > 0 {
            Text("还需 \(remaining) 天达标").font(.caption2).foregroundStyle(DesignSystem.textTertiary)
        } else if asset.dailyCost() <= asset.targetDailyCost {
            Text("已达到目标日成本").font(.caption2).foregroundStyle(DesignSystem.incomeColor)
        }
    }

    private var progressColor: Color {
        asset.progressToTarget() >= 1 ? DesignSystem.incomeColor : asset.progressToTarget() >= 0.6 ? .orange : DesignSystem.primaryColor
    }
}
