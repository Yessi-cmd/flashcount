import SwiftData
import SwiftUI

/// 展示未来现金余额变化。页面只读取本地快照，预测不会创建交易。
struct CashFlowForecastView: View {
    @EnvironmentObject private var privacyLock: PrivacyLockService
    @Query(sort: \CashPoolItem.sortOrder) private var cashPoolItems: [CashPoolItem]
    @Query(sort: \CashPoolState.updatedAt, order: .reverse) private var cashPoolStates: [CashPoolState]
    @Query(sort: \RecurringRule.nextDueDate) private var recurringRules: [RecurringRule]
    @Query private var occurrences: [RecurringOccurrence]
    @Query(sort: \InstallmentBill.createdAt, order: .reverse) private var installmentBills: [InstallmentBill]
    @Query private var recentTransactions: [Transaction]

    @AppStorage("payday") private var payday = 1
    @State private var horizon: CashFlowForecastHorizon = .thirtyDays
    @State private var mode: CashFlowForecastMode = .fixedAndRoutine

    init() {
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -120,
            to: Date.now
        ) ?? .distantPast
        _recentTransactions = Query(
            filter: #Predicate<Transaction> { $0.date >= cutoff },
            sort: \Transaction.date,
            order: .reverse
        )
    }

    private var forecast: CashFlowForecast {
        CashFlowForecastService.forecast(
            cashPoolItems: cashPoolItems,
            cashPoolState: cashPoolStates.first,
            recurringRules: recurringRules,
            occurrences: occurrences,
            installmentBills: installmentBills,
            transactions: recentTransactions,
            horizon: horizon,
            mode: mode,
            payday: payday
        )
    }

    private var hidesMoney: Bool {
        PrivacyVisibilityPolicy.hidesAssets(isUnlocked: privacyLock.isUnlocked)
    }

    var body: some View {
        ZStack {
            AmbientBackground(accent: DesignSystem.primaryColor)

            ScrollView {
                VStack(spacing: DesignSystem.sectionSpacing) {
                    CashFlowForecastControls(
                        horizon: $horizon,
                        mode: $mode
                    )
                    CashFlowForecastSummaryCard(
                        forecast: forecast,
                        hidesMoney: hidesMoney,
                        maskedText: privacyLock.maskedText
                    )
                    CashFlowRangeChart(forecast: forecast)
                    CashFlowForecastMethodCard(
                        forecast: forecast,
                        hidesMoney: hidesMoney,
                        maskedText: privacyLock.maskedText
                    )
                    cashFlowEvents
                }
                .padding()
            }
        }
        .navigationTitle("现金流预测")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                PrivacyVisibilityButton()
            }
        }
    }

    private var cashFlowEvents: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("未来已知事项")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.textSecondary)
                Spacer()
                Text("\(forecast.events.count) 项")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textTertiary)
            }

            if forecast.events.isEmpty {
                ContentUnavailableView(
                    "暂无已知现金流",
                    systemImage: "calendar.badge.plus",
                    description: Text("可以在周期账单或分期账单中添加未来事项")
                )
                .frame(maxWidth: .infinity)
                .glassCard()
            } else {
                ForEach(forecast.events.prefix(12)) { event in
                    CashFlowEventRow(
                        event: event,
                        hidesMoney: hidesMoney,
                        maskedText: privacyLock.maskedText
                    )
                }

                if forecast.events.count > 12 {
                    Text("另有 \(forecast.events.count - 12) 项，缩短预测范围可查看更近的事项")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
