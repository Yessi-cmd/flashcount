import SwiftUI
import SwiftData

/// 「这个数是怎么来的」。
/// 明细行由 `AssetPortfolioSnapshot` 产出，与卡片上的汇总来自同一次计算。
struct AssetBreakdownSheet: View {
    @Environment(\.dismiss) private var dismiss

    let kind: AssetBreakdownKind
    let lines: [AssetBreakdownLine]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(lines) { line in
                        if line.drillsIntoCashImpact {
                            NavigationLink {
                                CashImpactTransactionList(expectedDelta: line.amount)
                            } label: {
                                row(line)
                            }
                            .accessibilityIdentifier("assetBreakdown.drill.\(line.id)")
                        } else {
                            row(line)
                        }
                    }
                } footer: {
                    Text(kind.footnote)
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                        .accessibilityIdentifier("assetBreakdown.close")
                }
            }
        }
    }

    private func row(_ line: AssetBreakdownLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.label)
                    .font(line.style == .total ? .subheadline.weight(.semibold) : .subheadline)
                    .foregroundStyle(DesignSystem.textPrimary)
                if let detail = line.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.textTertiary)
                }
            }
            Spacer(minLength: 8)
            Text(line.amount.formattedCurrency)
                .font(
                    line.style == .total
                        ? .subheadline.weight(.bold).monospacedDigit()
                        : .subheadline.monospacedDigit()
                )
                .foregroundStyle(amountColor(line))
        }
        .padding(.vertical, line.style == .item ? 0 : 2)
        .accessibilityElement(children: .combine)
    }

    private func amountColor(_ line: AssetBreakdownLine) -> Color {
        switch line.style {
        case .total:
            return line.amount >= 0 ? DesignSystem.textPrimary : DesignSystem.expenseColor
        case .subtotal:
            return DesignSystem.textSecondary
        case .item:
            return line.amount < 0 ? DesignSystem.expenseColor : DesignSystem.textPrimary
        }
    }
}

/// 二级下钻：构成「记账增减」的交易。
/// 这个累计值从安装那天起就在后台累加，界面从不显示，
/// 数字对不上时用户此前没有任何查证手段。
struct CashImpactTransactionList: View {
    let expectedDelta: Decimal

    @Query(
        filter: #Predicate<Transaction> { $0.cashPoolDelta != nil },
        sort: \Transaction.date,
        order: .reverse
    ) private var transactions: [Transaction]

    private static let displayLimit = 100

    private var visible: [Transaction] {
        Array(transactions.prefix(Self.displayLimit))
    }

    private var transactionDelta: Decimal {
        transactions.reduce(Decimal.zero) { $0 + ($1.cashPoolDelta ?? 0) }
    }

    /// Calibration and legacy/imported state can contain an offset that has no
    /// transaction row. Show it explicitly so the drill-down still reconciles
    /// to the exact value used by the asset snapshot.
    private var unexplainedAdjustment: Decimal {
        expectedDelta - transactionDelta
    }

    var body: some View {
        List {
            Section {
                ForEach(visible, id: \.id) { transaction in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(transaction.note.isEmpty
                                 ? (transaction.category?.name ?? "未分类")
                                 : transaction.note)
                                .font(.subheadline)
                                .foregroundStyle(DesignSystem.textPrimary)
                                .lineLimit(1)
                            Text(transaction.date.shortDateString)
                                .font(.caption2)
                                .foregroundStyle(DesignSystem.textTertiary)
                        }
                        Spacer(minLength: 8)
                        Text((transaction.cashPoolDelta ?? 0).formattedCurrency)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(
                                (transaction.cashPoolDelta ?? 0) < 0
                                    ? DesignSystem.expenseColor
                                    : DesignSystem.incomeColor
                            )
                    }
                    .accessibilityElement(children: .combine)
                }

                if unexplainedAdjustment != 0 {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("校准/历史差额")
                                .font(.subheadline)
                                .foregroundStyle(DesignSystem.textPrimary)
                            Text("现金池累计值与交易明细的差额")
                                .font(.caption2)
                                .foregroundStyle(DesignSystem.textTertiary)
                        }
                        Spacer(minLength: 8)
                        Text(unexplainedAdjustment.formattedCurrency)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(
                                unexplainedAdjustment < 0
                                    ? DesignSystem.expenseColor
                                    : DesignSystem.incomeColor
                            )
                    }
                    .accessibilityElement(children: .combine)
                }
            } footer: {
                if transactions.count > visible.count {
                    Text("累计影响由全部 \(transactions.count) 笔记账和校准/历史差额构成，这里显示最近 \(visible.count) 笔。")
                } else {
                    Text("累计影响由这 \(transactions.count) 笔记账与校准/历史差额构成。")
                }
            }
        }
        .navigationTitle("记账增减")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("assetBreakdown.cashImpactList")
    }
}
