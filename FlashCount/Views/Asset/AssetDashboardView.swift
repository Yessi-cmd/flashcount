import SwiftUI
import SwiftData
import Charts

/// 资产全景图
struct AssetDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Asset.createdAt) private var assets: [Asset]
    @State private var showAddAsset = false
    @AppStorage("hideAssetBalance") private var hideBalance = true

    private var totalAssets: Decimal {
        assets.filter { !$0.type.isLiability && !$0.isArchived }.reduce(0) { $0 + $1.balance }
    }
    private var totalLiabilities: Decimal {
        assets.filter { $0.type.isLiability && !$0.isArchived }.reduce(0) { $0 + $1.balance }
    }
    private var netWorth: Decimal { totalAssets - totalLiabilities }
    private var assetItems: [Asset] { assets.filter { !$0.type.isLiability && !$0.isArchived } }
    private var liabilityItems: [Asset] { assets.filter { $0.type.isLiability && !$0.isArchived } }

    /// 隐藏金额的占位符
    private var maskedText: String { "****" }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: DesignSystem.sectionSpacing) {
                        netWorthCard

                        if !assetItems.isEmpty || !liabilityItems.isEmpty { assetBreakdown }
                        if !assetItems.isEmpty { assetSection(title: "资产", items: assetItems, color: DesignSystem.incomeColor) }
                        if !liabilityItems.isEmpty { assetSection(title: "负债", items: liabilityItems, color: DesignSystem.expenseColor) }

                        // 实物资产入口（和其他 section 统一风格）
                        NavigationLink {
                            PhysicalAssetView()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "iphone.and.arrow.forward")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Text("实物资产追踪")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.6))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.2))
                            }
                            .padding(.vertical, 8)
                        }

                        if assets.isEmpty { emptyState }
                    }
                    .padding()
                }
            }
            .navigationTitle("资产")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            hideBalance.toggle()
                        }
                    } label: {
                        Image(systemName: hideBalance ? "eye.slash.fill" : "eye.fill")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddAsset = true } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(DesignSystem.primaryColor)
                    }
                }
            }
            .sheet(isPresented: $showAddAsset) { AddAssetView() }
        }
    }

    private var netWorthCard: some View {
        VStack(spacing: 16) {
            Text("净资产").font(.subheadline).foregroundStyle(.white.opacity(0.5))
            if hideBalance {
                Text(maskedText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
            } else {
                Text(netWorth.formattedCurrency)
                    .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(netWorth >= 0 ? .white : DesignSystem.expenseColor)
            }
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("总资产").font(.caption).foregroundStyle(.white.opacity(0.4))
                    Text(hideBalance ? maskedText : totalAssets.formattedCurrency)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(DesignSystem.incomeColor)
                }
                Rectangle().fill(.white.opacity(0.1)).frame(width: 1, height: 30)
                VStack(spacing: 4) {
                    Text("总负债").font(.caption).foregroundStyle(.white.opacity(0.4))
                    Text(hideBalance ? maskedText : totalLiabilities.formattedCurrency)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(DesignSystem.expenseColor)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .glassCard()
    }

    private var assetBreakdown: some View {
        VStack(spacing: 12) {
            HStack {
                Text("资产构成").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.7))
                Spacer()
            }
            if !assetItems.isEmpty {
                Chart(assetItems, id: \.id) { asset in
                    SectorMark(angle: .value(asset.name, NSDecimalNumber(decimal: asset.balance).doubleValue), innerRadius: .ratio(0.6))
                        .foregroundStyle(Color(hex: asset.colorHex))
                }
                .frame(height: 180)
                .chartBackground { _ in
                    VStack {
                        Text("\(assetItems.count)").font(.title2.weight(.bold)).foregroundStyle(.white)
                        Text("账户").font(.caption).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .glassCard()
    }

    private func assetSection(title: String, items: [Asset], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(color)
            ForEach(items, id: \.id) { asset in
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color(hex: asset.colorHex).opacity(0.15)).frame(width: 40, height: 40)
                        Image(systemName: asset.icon).font(.subheadline).foregroundStyle(Color(hex: asset.colorHex))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.name).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                        Text(asset.type.rawValue).font(.caption).foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                    Text(hideBalance ? maskedText : asset.balance.formattedCurrency)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(color)
                }
                .padding(.vertical, 4)
                if asset.id != items.last?.id { Divider().background(.white.opacity(0.06)) }
            }
        }
        .glassCard()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.pie.fill").font(.system(size: 50)).foregroundStyle(.white.opacity(0.2))
            Text("暂无资产记录").font(.headline).foregroundStyle(.white.opacity(0.5))
            Text("添加你的银行卡、信用卡、理财等账户").font(.subheadline).foregroundStyle(.white.opacity(0.3))
            Button { showAddAsset = true } label: {
                Text("添加资产").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(DesignSystem.primaryGradient).clipShape(Capsule())
            }
        }.padding(.vertical, 60)
    }
}
