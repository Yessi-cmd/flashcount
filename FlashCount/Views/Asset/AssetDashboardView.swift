import SwiftUI
import SwiftData
import Charts

/// 资产全景图
struct AssetDashboardView: View {
    let isActive: Bool

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var privacyLock: PrivacyLockService
    @Query(sort: \Asset.createdAt) private var assets: [Asset]
    @Query(sort: \PhysicalAsset.purchaseDate, order: .reverse) private var physicalAssets: [PhysicalAsset]
    @Query(sort: \CashPoolItem.sortOrder) private var cashPoolItems: [CashPoolItem]
    @Query(sort: \CashPoolState.updatedAt, order: .reverse) private var cashPoolStates: [CashPoolState]
    @Query(sort: \SavingsGoal.createdAt, order: .reverse) private var savingsGoals: [SavingsGoal]
    @Query(sort: \InstallmentBill.createdAt, order: .reverse) private var installmentBills: [InstallmentBill]
    @State private var showAddCashPoolItem = false
    @State private var editingAsset: Asset?
    @State private var showTutorial = false
    @State private var didRequestInitialUnlock = false
    @AppStorage("hideAssetBalance") private var hideBalance = true

    private var legacyAssetTotal: Decimal {
        assets.filter { !$0.type.isLiability && !$0.isArchived }.reduce(0) { $0 + $1.balance }
    }
    private var legacyLiabilityTotal: Decimal {
        assets.filter { $0.type.isLiability && !$0.isArchived }.reduce(0) { $0 + $1.balance }
    }
    private var assetItems: [Asset] { assets.filter { !$0.type.isLiability && !$0.isArchived } }
    private var liabilityItems: [Asset] { assets.filter { $0.type.isLiability && !$0.isArchived } }
    private var activePhysicalAssets: [PhysicalAsset] { physicalAssets.filter { !$0.isArchived } }
    private var physicalTotalValue: Decimal {
        activePhysicalAssets.reduce(Decimal(0)) { $0 + $1.currentValue }
    }
    private var physicalPurchaseTotal: Decimal {
        activePhysicalAssets.reduce(Decimal(0)) { $0 + $1.purchasePrice }
    }
    private var physicalAverageDailyCost: Decimal {
        guard !activePhysicalAssets.isEmpty else { return 0 }
        return activePhysicalAssets.reduce(Decimal(0)) { $0 + $1.dailyCost } / Decimal(activePhysicalAssets.count)
    }
    private var activeCashPoolItems: [CashPoolItem] { cashPoolItems.filter { !$0.isArchived } }
    private var cashPoolManualTotal: Decimal {
        activeCashPoolItems.reduce(Decimal(0)) { $0 + $1.signedAmount }
    }
    private var cashPoolPositiveTotal: Decimal {
        activeCashPoolItems.filter { !$0.kind.isNegative }.reduce(Decimal(0)) { $0 + $1.amount }
    }
    private var cashPoolManualLiabilityTotal: Decimal {
        activeCashPoolItems.filter { $0.kind.isNegative }.reduce(Decimal(0)) { $0 + $1.amount }
    }
    private var cashPoolTransactionDelta: Decimal {
        cashPoolStates.first?.transactionDelta ?? 0
    }
    private var liquidAssetTotal: Decimal {
        max(cashPoolPositiveTotal + cashPoolTransactionDelta, 0)
    }
    private var liquidLiabilityTotal: Decimal {
        cashPoolManualLiabilityTotal + installmentRemainingTotal + max(-(cashPoolPositiveTotal + cashPoolTransactionDelta), 0)
    }
    private var activeInstallmentBills: [InstallmentBill] { installmentBills.filter { !$0.isArchived } }
    private var installmentRemainingTotal: Decimal {
        activeInstallmentBills.reduce(Decimal(0)) { $0 + $1.remainingAmount }
    }
    private var cashPoolAvailable: Decimal {
        cashPoolManualTotal + cashPoolTransactionDelta - installmentRemainingTotal
    }
    private var totalAssets: Decimal {
        liquidAssetTotal + legacyAssetTotal
    }
    private var totalLiabilities: Decimal {
        liquidLiabilityTotal + legacyLiabilityTotal
    }
    private var netWorth: Decimal {
        totalAssets - totalLiabilities
    }
    private var activeSavingsGoals: [SavingsGoal] { savingsGoals.filter { !$0.isArchived } }
    private var savingsTargetTotal: Decimal {
        activeSavingsGoals.reduce(Decimal(0)) { $0 + $1.targetAmount }
    }
    private var savingsCurrentTotal: Decimal {
        activeSavingsGoals.reduce(Decimal(0)) { $0 + $1.currentAmount }
    }

    /// 隐藏金额的占位符
    private var maskedText: String { "****" }
    private var hidesAssetMoney: Bool { hideBalance || !privacyLock.isUnlocked }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: DesignSystem.sectionSpacing) {
                        netWorthCard
                        cashPoolSummary
                        if !activeSavingsGoals.isEmpty { savingsGoalSummary }

                        if !assetItems.isEmpty || !liabilityItems.isEmpty { assetBreakdown }
                        if !assetItems.isEmpty { assetSection(title: "资产", items: assetItems, color: DesignSystem.incomeColor) }
                        if !liabilityItems.isEmpty { assetSection(title: "负债", items: liabilityItems, color: DesignSystem.expenseColor) }
                        if !activePhysicalAssets.isEmpty { physicalAssetSummary }

                        // 更多工具
                        VStack(alignment: .leading, spacing: 12) {
                            Text("资产工具").font(.subheadline.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)

                            NavigationLink {
                                PhysicalAssetView()
                            } label: {
                                toolRow(icon: "iphone.and.arrow.forward", color: .orange, title: "实物资产", subtitle: "手机、电脑、汽车的日均成本")
                            }
                            NavigationLink {
                                CashPoolView()
                            } label: {
                                toolRow(icon: "wallet.pass.fill", color: DesignSystem.primaryColor, title: "资金池", subtitle: "统一管理可动用资金")
                            }
                            NavigationLink {
                                InstallmentBillView()
                            } label: {
                                toolRow(icon: "creditcard.trianglebadge.exclamationmark.fill", color: DesignSystem.expenseColor, title: "分期账单", subtitle: "记录每笔分期、期数与还款日")
                            }
                            NavigationLink {
                                SavingsGoalView()
                            } label: {
                                toolRow(icon: "target", color: DesignSystem.incomeColor, title: "储蓄目标", subtitle: "手动追踪存钱计划")
                            }
                        }

                        if activeCashPoolItems.isEmpty && activePhysicalAssets.isEmpty && activeSavingsGoals.isEmpty && activeInstallmentBills.isEmpty && assets.isEmpty {
                            emptyState
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("资产")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if privacyLock.isUnlocked {
                            withAnimation(.spring(response: 0.3)) {
                                hideBalance.toggle()
                            }
                        } else {
                            Task {
                                if await privacyLock.unlock() {
                                    hideBalance = false
                                }
                            }
                        }
                    } label: {
                        Image(systemName: hidesAssetMoney ? "eye.slash.fill" : "eye.fill")
                            .foregroundStyle(DesignSystem.textSecondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button { showTutorial = true } label: {
                            Image(systemName: "questionmark.circle.fill")
                                .foregroundStyle(DesignSystem.textSecondary)
                        }
                        Button { showAddCashPoolItem = true } label: {
                            Image(systemName: "plus.circle.fill").foregroundStyle(DesignSystem.primaryColor)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddCashPoolItem) {
                AddCashPoolItemView(nextSortOrder: cashPoolItems.count)
            }
            .sheet(isPresented: $showTutorial) { TutorialView() }
            .sheet(item: $editingAsset) { asset in
                AddAssetView(editAsset: asset)
            }
            .task(id: isActive) {
                guard isActive else { return }
                await requestInitialUnlockIfNeeded()
            }
        }
    }

    private var netWorthCard: some View {
        VStack(spacing: 16) {
            Text("净资产").font(.subheadline).foregroundStyle(DesignSystem.textSecondary)
            if hidesAssetMoney {
                Text(privacyLock.maskedText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignSystem.textTertiary)
            } else {
                Text(netWorth.formattedCurrency)
                    .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(netWorth >= 0 ? DesignSystem.textPrimary : DesignSystem.expenseColor)
            }
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("总资产").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                    Text(hidesAssetMoney ? privacyLock.maskedText : totalAssets.formattedCurrency)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(DesignSystem.incomeColor)
                }
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 30)
                VStack(spacing: 4) {
                    Text("总负债").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                    Text(hidesAssetMoney ? privacyLock.maskedText : totalLiabilities.formattedCurrency)
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
                Text("资产构成").font(.subheadline.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
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
                        Text("\(assetItems.count)").font(.title2.weight(.bold)).foregroundStyle(DesignSystem.textPrimary)
                        Text("账户").font(.caption).foregroundStyle(DesignSystem.textSecondary)
                    }
                }
            }
        }
        .glassCard()
    }

    private var physicalAssetSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("实物资产", systemImage: "iphone.and.arrow.forward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
                Spacer()
                Text("\(activePhysicalAssets.count) 件")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DesignSystem.primaryColor)
            }

            HStack(spacing: 0) {
                physicalMetric(title: "当前估值", value: hidesAssetMoney ? privacyLock.maskedText : physicalTotalValue.formattedCurrency, color: DesignSystem.primaryColor)
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 32)
                physicalMetric(title: "总折旧", value: hidesAssetMoney ? privacyLock.maskedText : (physicalPurchaseTotal - physicalTotalValue).formattedCurrency, color: DesignSystem.expenseColor)
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 32)
                physicalMetric(title: "平均日成本", value: hidesAssetMoney ? privacyLock.maskedText : physicalAverageDailyCost.formattedCurrency, color: DesignSystem.warningColor)
            }
        }
        .glassCard()
    }

    private var cashPoolSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("资金池", systemImage: "wallet.pass.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
                Spacer()
            }

            HStack(spacing: 0) {
                privateMetric(title: "可动用资金", value: cashPoolAvailable, color: DesignSystem.primaryColor)
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 32)
                privateMetric(title: "资金净额", value: cashPoolManualTotal, color: DesignSystem.incomeColor)
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 32)
                privateMetric(title: "分期待还", value: installmentRemainingTotal, color: DesignSystem.expenseColor)
            }
        }
        .glassCard()
    }

    private var savingsGoalSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("储蓄目标", systemImage: "target")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
                Spacer()
                Text("\(activeSavingsGoals.count) 个")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DesignSystem.primaryColor)
            }

            HStack(spacing: 0) {
                privateMetric(title: "已存", value: savingsCurrentTotal, color: DesignSystem.incomeColor)
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 32)
                privateMetric(title: "目标", value: savingsTargetTotal, color: DesignSystem.primaryColor)
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 32)
                privateMetric(title: "还差", value: max(savingsTargetTotal - savingsCurrentTotal, 0), color: DesignSystem.warningColor)
            }
        }
        .glassCard()
    }

    private func privateMetric(title: String, value: Decimal, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(DesignSystem.textTertiary)
            Text(hidesAssetMoney ? privacyLock.maskedText : value.formattedCurrency)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
    }

    private func physicalMetric(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(DesignSystem.textTertiary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
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
                        Text(asset.name).font(.subheadline.weight(.medium)).foregroundStyle(DesignSystem.textPrimary)
                        Text(asset.type.rawValue).font(.caption).foregroundStyle(DesignSystem.textTertiary)
                    }
                    Spacer()
                    Text(hidesAssetMoney ? privacyLock.maskedText : asset.balance.formattedCurrency)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(color)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture { editingAsset = asset }
                .contextMenu {
                    Button {
                        editingAsset = asset
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        withAnimation {
                            modelContext.delete(asset)
                            try? modelContext.save()
                        }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                if asset.id != items.last?.id { Divider().background(DesignSystem.softFill) }
            }
        }
        .glassCard()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.pie.fill").font(.system(size: 50)).foregroundStyle(DesignSystem.textTertiary)
            Text("暂无资产记录").font(.headline).foregroundStyle(DesignSystem.textSecondary)
            Text("先盘点现金、银行卡合计或可动用理财").font(.subheadline).foregroundStyle(DesignSystem.textTertiary)
            Button { showAddCashPoolItem = true } label: {
                Text("添加资金项").font(.subheadline.weight(.semibold)).foregroundStyle(DesignSystem.textPrimary)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(DesignSystem.primaryGradient).clipShape(Capsule())
            }
        }.padding(.vertical, 60)
    }

    private func toolRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(DesignSystem.textPrimary)
                Text(subtitle).font(.caption2).foregroundStyle(DesignSystem.textTertiary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(DesignSystem.textTertiary)
        }
        .padding(.vertical, 4)
    }

    private func requestInitialUnlockIfNeeded() async {
        guard !didRequestInitialUnlock else { return }
        didRequestInitialUnlock = true
        guard !privacyLock.isUnlocked else {
            hideBalance = false
            return
        }
        if await privacyLock.unlock() {
            hideBalance = false
        }
    }
}

// MARK: - 虚拟资产（占位）
struct VirtualAssetListView: View {
    var body: some View {
        ZStack {
            DesignSystem.surfaceBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "sparkles").font(.system(size: 50)).foregroundStyle(.cyan.opacity(0.3))
                Text("虚拟资产").font(.headline).foregroundStyle(DesignSystem.textSecondary)
                Text("即将上线，敬请期待 🚀").font(.subheadline).foregroundStyle(DesignSystem.textTertiary)
            }
        }
        .navigationTitle("虚拟资产")
        .navigationBarTitleDisplayMode(.large)
    }
}
