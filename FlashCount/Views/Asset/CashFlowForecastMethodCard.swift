import SwiftUI

struct CashFlowForecastMethodCard: View {
    @State private var showsMethod = false

    let forecast: CashFlowForecast
    let hidesMoney: Bool
    let maskedText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("这不是一条假装精确的线", systemImage: "scope")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.textPrimary)

            Text("已知账单按日期精确落点；日常支出用完整记录周形成较低、典型、较高三种历史节奏。")
                .font(.caption)
                .foregroundStyle(DesignSystem.textSecondary)

            Button {
                showsMethod = true
            } label: {
                HStack {
                    Text("查看计算方法")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignSystem.primaryColor)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cashFlow.method")
            .sheet(isPresented: $showsMethod) {
                CashFlowForecastMethodView(
                    forecast: forecast,
                    hidesMoney: hidesMoney,
                    maskedText: maskedText
                )
            }
        }
        .glassCard()
    }
}

private struct CashFlowForecastMethodView: View {
    @Environment(\.dismiss) private var dismiss

    let forecast: CashFlowForecast
    let hidesMoney: Bool
    let maskedText: String

    var body: some View {
        NavigationStack {
            List {
                Section("已知事项") {
                    methodRow(
                        title: "固定收入",
                        value: displayAmount(forecast.confirmedIncome)
                    )
                    methodRow(
                        title: "固定支出",
                        value: displayAmount(forecast.confirmedExpense)
                    )
                    Text("来自启用中的周期账单和未完成分期，按各自日期计入。")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textSecondary)
                }

                Section("日常支出样本") {
                    if let profile = forecast.routineProfile {
                        methodRow(
                            title: "完整记录周",
                            value: "\(profile.observedWeekCount) 周"
                        )
                        methodRow(
                            title: "纳入交易",
                            value: "\(profile.qualifyingTransactionCount) 笔"
                        )
                        methodRow(
                            title: "较低支出（P20）",
                            value: displayAmount(profile.lighterWeeklyExpense)
                        )
                        methodRow(
                            title: "典型支出（P50）",
                            value: displayAmount(profile.typicalWeeklyExpense)
                        )
                        methodRow(
                            title: "较高支出（P80）",
                            value: displayAmount(profile.higherWeeklyExpense)
                        )
                    } else {
                        ContentUnavailableView(
                            "暂无完整周样本",
                            systemImage: "calendar.badge.exclamationmark",
                            description: Text("继续日常记账后，这里会自动形成历史节奏")
                        )
                    }
                }

                Section("口径说明") {
                    Label(
                        "只纳入日常预算范围内的普通支出；周期账单不会重复进入历史节奏。",
                        systemImage: "checkmark.circle"
                    )
                    Label(
                        "当前未结束的一周不参与计算，整周完全没有记录时按缺失样本跳过。",
                        systemImage: "calendar"
                    )
                    Label(
                        "P20–P80 是历史常见范围，不是概率、置信区间或余额保证。",
                        systemImage: "exclamationmark.bubble"
                    )
                    Label(
                        "预测从明天开始估算日常支出，避免把今天当成完整一天。",
                        systemImage: "sunrise"
                    )
                }
                .font(.subheadline)
                .foregroundStyle(DesignSystem.textSecondary)
            }
            .navigationTitle("计算方法")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func methodRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(DesignSystem.textSecondary)
                .monospacedDigit()
                .privacySensitive(hidesMoney)
        }
    }

    private func displayAmount(_ amount: Decimal) -> String {
        hidesMoney ? maskedText : amount.formattedCurrency
    }
}
