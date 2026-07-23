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
    @State private var confirmDeleteAsset: Asset?

    /// 单次遍历构建页面需要的资产快照，避免每个卡片再次 filter/reduce 同一批 SwiftData 结果。
    private struct DashboardSnapshot {
        let assetItems: [Asset]
        let liabilityItems: [Asset]
        let activePhysicalAssets: [PhysicalAsset]
        let activeCashPoolItems: [CashPoolItem]
        let activeSavingsGoals: [SavingsGoal]
        let activeInstallmentBills: [InstallmentBill]
        let physicalTotalValue: Decimal
        let physicalPurchaseTotal: Decimal
        let physicalAverageDailyCost: Decimal
        let cashPoolManualTotal: Decimal
        let installmentRemainingTotal: Decimal
        let cashPoolAvailable: Decimal
        let totalAssets: Decimal
        let totalLiabilities: Decimal
        let netWorth: Decimal
        let savingsTargetTotal: Decimal
        let savingsCurrentTotal: Decimal

        init(
            assets: [Asset],
            physicalAssets: [PhysicalAsset],
            cashPoolItems: [CashPoolItem],
            cashPoolTransactionDelta: Decimal,
            savingsGoals: [SavingsGoal],
            installmentBills: [InstallmentBill]
        ) {
            var assetItems: [Asset] = []
            var liabilityItems: [Asset] = []
            var legacyAssetTotal: Decimal = 0
            var legacyLiabilityTotal: Decimal = 0
            for asset in assets where !asset.isArchived {
                if asset.type.isLiability {
                    liabilityItems.append(asset)
                    legacyLiabilityTotal += asset.balance
                } else {
                    assetItems.append(asset)
                    legacyAssetTotal += asset.balance
                }
            }

            let activePhysicalAssets = physicalAssets.filter { !$0.isArchived }
            let physicalTotalValue = activePhysicalAssets.reduce(Decimal(0)) { $0 + $1.currentValue }
            let physicalPurchaseTotal = activePhysicalAssets.reduce(Decimal(0)) { $0 + $1.purchasePrice }
            let physicalDailyCostTotal = activePhysicalAssets.reduce(Decimal(0)) { $0 + $1.dailyCost }

            let activeCashPoolItems = cashPoolItems.filter { !$0.isArchived }
            var cashPoolManualTotal: Decimal = 0
            var cashPoolPositiveTotal: Decimal = 0
            var cashPoolManualLiabilityTotal: Decimal = 0
            for item in activeCashPoolItems {
                cashPoolManualTotal += item.signedAmount
                if item.kind.isNegative {
                    cashPoolManualLiabilityTotal += item.amount
                } else {
                    cashPoolPositiveTotal += item.amount
                }
            }

            let activeInstallmentBills = installmentBills.filter { !$0.isArchived }
            let installmentRemainingTotal = activeInstallmentBills.reduce(Decimal(0)) { $0 + $1.remainingAmount }
            let liquidNet = cashPoolPositiveTotal + cashPoolTransactionDelta
            let liquidAssetTotal = max(liquidNet, 0)
            let liquidLiabilityTotal = cashPoolManualLiabilityTotal + installmentRemainingTotal + max(-liquidNet, 0)

            let activeSavingsGoals = savingsGoals.filter { !$0.isArchived }
            let savingsTargetTotal = activeSavingsGoals.reduce(Decimal(0)) { $0 + $1.targetAmount }
            let savingsCurrentTotal = activeSavingsGoals.reduce(Decimal(0)) { $0 + $1.currentAmount }

            self.assetItems = assetItems
            self.liabilityItems = liabilityItems
            self.activePhysicalAssets = activePhysicalAssets
            self.activeCashPoolItems = activeCashPoolItems
            self.activeSavingsGoals = activeSavingsGoals
            self.activeInstallmentBills = activeInstallmentBills
            self.physicalTotalValue = physicalTotalValue
            self.physicalPurchaseTotal = physicalPurchaseTotal
            self.physicalAverageDailyCost = activePhysicalAssets.isEmpty ? 0 : physicalDailyCostTotal / Decimal(activePhysicalAssets.count)
            self.cashPoolManualTotal = cashPoolManualTotal
            self.installmentRemainingTotal = installmentRemainingTotal
            self.cashPoolAvailable = cashPoolManualTotal + cashPoolTransactionDelta - installmentRemainingTotal
            self.totalAssets = liquidAssetTotal + legacyAssetTotal
            self.totalLiabilities = liquidLiabilityTotal + legacyLiabilityTotal
            self.netWorth = self.totalAssets - self.totalLiabilities
            self.savingsTargetTotal = savingsTargetTotal
            self.savingsCurrentTotal = savingsCurrentTotal
        }
    }

    /// 隐藏金额的占位符
    private var maskedText: String { "****" }
    private var hidesAssetMoney: Bool {
        PrivacyVisibilityPolicy.hidesAssets(isUnlocked: privacyLock.isUnlocked)
    }

    var body: some View {
        let snapshot = DashboardSnapshot(
            assets: assets,
            physicalAssets: physicalAssets,
            cashPoolItems: cashPoolItems,
            cashPoolTransactionDelta: cashPoolStates.first?.transactionDelta ?? 0,
            savingsGoals: savingsGoals,
            installmentBills: installmentBills
        )

        return NavigationStack {
            ZStack {
                AmbientBackground(accent: DesignSystem.incomeColor)
                ScrollView {
                    VStack(spacing: DesignSystem.sectionSpacing) {
                        netWorthCard(snapshot)
                        cashPoolSummary(snapshot)
                        if !snapshot.activeSavingsGoals.isEmpty { savingsGoalSummary(snapshot) }

                        if !snapshot.assetItems.isEmpty || !snapshot.liabilityItems.isEmpty { assetBreakdown(snapshot) }
                        if !snapshot.assetItems.isEmpty { assetSection(title: "资产", items: snapshot.assetItems, color: DesignSystem.incomeColor) }
                        if !snapshot.liabilityItems.isEmpty { assetSection(title: "负债", items: snapshot.liabilityItems, color: DesignSystem.expenseColor) }
                        if !snapshot.activePhysicalAssets.isEmpty { physicalAssetSummary(snapshot) }

                        // 更多工具
                        VStack(alignment: .leading, spacing: 12) {
                            Text("资产工具").font(.subheadline.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)

                            NavigationLink {
                                PhysicalAssetView()
                            } label: {
                                toolRow(icon: "iphone.and.arrow.forward", color: DesignSystem.primaryColor, title: "实物资产", subtitle: "手机、电脑、汽车的日均成本")
                            }
                            NavigationLink {
                                CashPoolView()
                            } label: {
                                toolRow(icon: "wallet.pass.fill", color: DesignSystem.primaryColor, title: "资金池", subtitle: "统一管理可动用资金")
                            }
                            NavigationLink {
                                InstallmentBillView()
                            } label: {
                                toolRow(icon: "creditcard.trianglebadge.exclamationmark.fill", color: DesignSystem.primaryColor, title: "分期账单", subtitle: "记录每笔分期、期数与还款日")
                            }
                            NavigationLink {
                                SavingsGoalView()
                            } label: {
                                toolRow(icon: "target", color: DesignSystem.primaryColor, title: "储蓄目标", subtitle: "手动追踪存钱计划")
                            }
                        }

                        if snapshot.activeCashPoolItems.isEmpty && snapshot.activePhysicalAssets.isEmpty && snapshot.activeSavingsGoals.isEmpty && snapshot.activeInstallmentBills.isEmpty && assets.isEmpty {
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
                    PrivacyVisibilityButton()
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
            .alert("确认删除", isPresented: .init(
                get: { confirmDeleteAsset != nil },
                set: { if !$0 { confirmDeleteAsset = nil } }
            )) {
                Button("取消", role: .cancel) { confirmDeleteAsset = nil }
                Button("删除", role: .destructive) {
                    if let asset = confirmDeleteAsset {
                        withAnimation {
                            modelContext.delete(asset)
                            if let error = safeSave(modelContext) {
                                print("删除账户失败: \(error)")
                            }
                        }
                    }
                    confirmDeleteAsset = nil
                }
            } message: {
                Text("删除后无法恢复，确定要删除「\(confirmDeleteAsset?.name ?? "")」吗？")
            }
        }
    }

    private func netWorthCard(_ snapshot: DashboardSnapshot) -> some View {
        VStack(spacing: 16) {
            Text("净资产").font(.subheadline).foregroundStyle(DesignSystem.textSecondary)
            if hidesAssetMoney {
                Text(privacyLock.maskedText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignSystem.textTertiary)
            } else {
                Text(snapshot.netWorth.formattedCurrency)
                    .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(snapshot.netWorth >= 0 ? DesignSystem.textPrimary : DesignSystem.expenseColor)
            }
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("总资产").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                    Text(hidesAssetMoney ? privacyLock.maskedText : snapshot.totalAssets.formattedCurrency)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(DesignSystem.incomeColor)
                }
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 30)
                VStack(spacing: 4) {
                    Text("总负债").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                    Text(hidesAssetMoney ? privacyLock.maskedText : snapshot.totalLiabilities.formattedCurrency)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(DesignSystem.expenseColor)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .heroCard(accent: hidesAssetMoney ? DesignSystem.primaryColor : (snapshot.netWorth >= 0 ? DesignSystem.incomeColor : DesignSystem.expenseColor))
    }

    private func assetBreakdown(_ snapshot: DashboardSnapshot) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("资产构成").font(.subheadline.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
                Spacer()
            }
            if hidesAssetMoney {
                VStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.title2)
                        .foregroundStyle(DesignSystem.textTertiary)
                    Text("验证后显示资产构成")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
            } else if !snapshot.assetItems.isEmpty {
                Chart(snapshot.assetItems, id: \.id) { asset in
                    SectorMark(angle: .value(asset.name, NSDecimalNumber(decimal: asset.balance).doubleValue), innerRadius: .ratio(0.6))
                        .foregroundStyle(Color(hex: asset.colorHex))
                }
                .frame(height: 180)
                .chartBackground { _ in
                    VStack {
                        Text("\(snapshot.assetItems.count)").font(.title2.weight(.bold)).foregroundStyle(DesignSystem.textPrimary)
                        Text("账户").font(.caption).foregroundStyle(DesignSystem.textSecondary)
                    }
                }
            }
        }
        .glassCard()
    }

    private func physicalAssetSummary(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("实物资产", systemImage: "iphone.and.arrow.forward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
                Spacer()
                Text("\(snapshot.activePhysicalAssets.count) 件")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DesignSystem.primaryColor)
            }

            HStack(spacing: 0) {
                physicalMetric(title: "当前估值", value: hidesAssetMoney ? privacyLock.maskedText : snapshot.physicalTotalValue.formattedCurrency, color: DesignSystem.primaryColor)
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 32)
                physicalMetric(title: "总折旧", value: hidesAssetMoney ? privacyLock.maskedText : (snapshot.physicalPurchaseTotal - snapshot.physicalTotalValue).formattedCurrency, color: DesignSystem.expenseColor)
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 32)
                physicalMetric(title: "平均日成本", value: hidesAssetMoney ? privacyLock.maskedText : snapshot.physicalAverageDailyCost.formattedCurrency, color: DesignSystem.warningColor)
            }
        }
        .glassCard()
    }

    private func cashPoolSummary(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("资金池", systemImage: "wallet.pass.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
                Spacer()
            }

            HStack(spacing: 0) {
                privateMetric(title: "可动用资金", value: snapshot.cashPoolAvailable, color: DesignSystem.primaryColor)
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 32)
                privateMetric(title: "资金净额", value: snapshot.cashPoolManualTotal, color: DesignSystem.incomeColor)
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 32)
                privateMetric(title: "分期待还", value: snapshot.installmentRemainingTotal, color: DesignSystem.expenseColor)
            }
        }
        .glassCard()
    }

    private func savingsGoalSummary(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("储蓄目标", systemImage: "target")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
                Spacer()
                Text("\(snapshot.activeSavingsGoals.count) 个")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DesignSystem.primaryColor)
            }

            HStack(spacing: 0) {
                privateMetric(title: "已存", value: snapshot.savingsCurrentTotal, color: DesignSystem.incomeColor)
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 32)
                privateMetric(title: "目标", value: snapshot.savingsTargetTotal, color: DesignSystem.primaryColor)
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 32)
                privateMetric(title: "还差", value: max(snapshot.savingsTargetTotal - snapshot.savingsCurrentTotal, 0), color: DesignSystem.warningColor)
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
                .onTapGesture { revealOrPerform { editingAsset = asset } }
                .accessibilityAddTraits(.isButton)
                .contextMenu {
                    Button {
                        revealOrPerform { editingAsset = asset }
                    } label: {
                        Label(hidesAssetMoney ? "验证后编辑" : "编辑", systemImage: hidesAssetMoney ? "lock.open" : "pencil")
                    }
                    Button(role: .destructive) {
                        confirmDeleteAsset = asset
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
                Text("添加资金项").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(DesignSystem.primaryColor)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
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

    private func revealOrPerform(_ action: () -> Void) {
        guard privacyLock.isUnlocked else {
            privacyLock.requestReveal()
            return
        }
        action()
    }
}

// MARK: - 虚拟资产（占位）
struct VirtualAssetListView: View {
    var body: some View {
        ZStack {
            DesignSystem.surfaceBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "sparkles").font(.system(size: 50)).foregroundStyle(DesignSystem.primaryColor.opacity(0.45))
                Text("虚拟资产").font(.headline).foregroundStyle(DesignSystem.textSecondary)
                Text("即将上线，敬请期待").font(.subheadline).foregroundStyle(DesignSystem.textTertiary)
            }
        }
        .navigationTitle("虚拟资产")
        .navigationBarTitleDisplayMode(.large)
    }
}
