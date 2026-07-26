import SwiftUI
import SwiftData

/// 资产全景图
struct AssetDashboardView: View {
    let isActive: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var privacyLock: PrivacyLockService
    @Query(sort: \PhysicalAsset.purchaseDate, order: .reverse) private var physicalAssets: [PhysicalAsset]
    @Query(sort: \CashPoolItem.sortOrder) private var cashPoolItems: [CashPoolItem]
    @Query(sort: \CashPoolState.updatedAt, order: .reverse) private var cashPoolStates: [CashPoolState]
    @Query(sort: \SavingsGoal.createdAt, order: .reverse) private var savingsGoals: [SavingsGoal]
    @Query(sort: \InstallmentBill.createdAt, order: .reverse) private var installmentBills: [InstallmentBill]
    @State private var showAddCashPoolItem = false
    @State private var showTutorial = false

    private var hidesAssetMoney: Bool {
        PrivacyVisibilityPolicy.hidesAssets(isUnlocked: privacyLock.isUnlocked)
    }

    var body: some View {
        let snapshot = AssetPortfolioSnapshot(
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
                        cashFlowForecastCard
                        if !snapshot.activeSavingsGoals.isEmpty { savingsGoalSummary(snapshot) }
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

                        if snapshot.isEmpty {
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
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("资产说明")
                        .accessibilityIdentifier("assets.tutorial")
                        Button { showAddCashPoolItem = true } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(DesignSystem.primaryColor)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("添加资金项")
                        .accessibilityIdentifier("assets.addCashPoolItem")
                    }
                }
            }
            .sheet(isPresented: $showAddCashPoolItem) {
                AddCashPoolItemView(nextSortOrder: cashPoolItems.count)
            }
            .sheet(isPresented: $showTutorial) { TutorialView() }
        }
    }

    private func netWorthCard(_ snapshot: AssetPortfolioSnapshot) -> some View {
        VStack(spacing: 16) {
            Text("净资产").font(.subheadline).foregroundStyle(DesignSystem.textSecondary)
            if hidesAssetMoney {
                Text(privacyLock.maskedText)
                    .font(DesignSystem.Typography.amount)
                    .foregroundStyle(DesignSystem.textTertiary)
            } else {
                Text(snapshot.netWorth.formattedCurrency)
                    .font(DesignSystem.Typography.amount).monospacedDigit()
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

            // 净资产只统计可动用资金与负债；实物资产和储蓄目标另算，
            // 不写清楚的话，卡片上明明有估值却不进总数，看起来就像算错了。
            Text("按资金池口径统计，不含实物资产估值与储蓄目标")
                .font(.caption2)
                .foregroundStyle(DesignSystem.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .heroCard(accent: hidesAssetMoney ? DesignSystem.primaryColor : (snapshot.netWorth >= 0 ? DesignSystem.incomeColor : DesignSystem.expenseColor))
    }

    private func physicalAssetSummary(_ snapshot: AssetPortfolioSnapshot) -> some View {
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
                // 合计而非平均：用户想知道「这些东西每天一共花我多少」。
                physicalMetric(title: "每日合计成本", value: hidesAssetMoney ? privacyLock.maskedText : snapshot.physicalDailyCostTotal.formattedCurrency, color: DesignSystem.warningColor)
            }
        }
        .glassCard()
    }

    private func cashPoolSummary(_ snapshot: AssetPortfolioSnapshot) -> some View {
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

    private var cashFlowForecastCard: some View {
        NavigationLink {
            CashFlowForecastView()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(DesignSystem.primaryColor.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(DesignSystem.primaryColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("现金流预测")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.textPrimary)
                    Text("查看未来余额、固定支出和现金低点")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textSecondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.textTertiary)
            }
            .glassCard()
        }
        .buttonStyle(.plain)
    }

    private func savingsGoalSummary(_ snapshot: AssetPortfolioSnapshot) -> some View {
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
}
