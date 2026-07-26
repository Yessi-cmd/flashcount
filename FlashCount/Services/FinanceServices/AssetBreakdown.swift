import Foundation

/// 资产页汇总数字的构成明细。
///
/// 「可动用资金 = 资金净额 + 交易增减 − 分期待还」这个公式此前只存在于代码里，
/// 其中「交易增减」还是个从安装起就在后台累加、界面从不显示的计数器。
/// 数字对不上时，用户唯一的出路是「校准」——把差异抹平而不是解释差异。
/// 这些明细行就是那个缺失的诊断视图。
struct AssetBreakdownLine: Identifiable, Equatable {
    enum Style: Equatable {
        case item
        case subtotal
        case total
    }

    let id: String
    let label: String
    let detail: String?
    let amount: Decimal
    let style: Style
    /// 该行能否继续下钻到具体交易。目前只有「记账增减」可以。
    let drillsIntoCashImpact: Bool

    init(
        id: String,
        label: String,
        detail: String? = nil,
        amount: Decimal,
        style: Style = .item,
        drillsIntoCashImpact: Bool = false
    ) {
        self.id = id
        self.label = label
        self.detail = detail
        self.amount = amount
        self.style = style
        self.drillsIntoCashImpact = drillsIntoCashImpact
    }
}

enum AssetBreakdownKind: String, Identifiable, CaseIterable {
    case availableFunds
    case totalAssets
    case totalLiabilities

    var id: String { rawValue }

    var title: String {
        switch self {
        case .availableFunds: return "可动用资金"
        case .totalAssets: return "总资产"
        case .totalLiabilities: return "总负债"
        }
    }

    var footnote: String {
        switch self {
        case .availableFunds:
            return "可动用资金 = 资金净额 + 记账增减 − 分期待还。若这里的数字和你的实际情况不符，先看看是哪一项对不上，再决定要不要校准。"
        case .totalAssets:
            return "只统计资金池里的正向资金，不含实物资产估值与储蓄目标。"
        case .totalLiabilities:
            return "手工登记的负债、未还清的分期，以及记账超支的部分。"
        }
    }
}

extension AssetPortfolioSnapshot {
    /// 明细行的合计必须等于对应的汇总数字——`AssetBreakdownTests` 对每一种都做了校验。
    func breakdown(_ kind: AssetBreakdownKind) -> [AssetBreakdownLine] {
        switch kind {
        case .availableFunds: return availableFundsLines()
        case .totalAssets: return totalAssetsLines()
        case .totalLiabilities: return totalLiabilitiesLines()
        }
    }

    private func availableFundsLines() -> [AssetBreakdownLine] {
        var lines = activeCashPoolItems.map { item in
            AssetBreakdownLine(
                id: "item-\(item.id.uuidString)",
                label: item.name,
                detail: item.kind.displayName,
                amount: item.signedAmount
            )
        }
        lines.append(AssetBreakdownLine(
            id: "manual-subtotal",
            label: "资金净额",
            detail: "手工登记的资金项合计",
            amount: cashPoolManualTotal,
            style: .subtotal
        ))
        lines.append(AssetBreakdownLine(
            id: "transaction-delta",
            label: "记账增减",
            detail: "自安装以来所有记账对现金的累计影响",
            amount: cashPoolTransactionDelta,
            drillsIntoCashImpact: true
        ))
        lines.append(AssetBreakdownLine(
            id: "installment-remaining",
            label: "分期待还",
            detail: installmentDetail,
            amount: -installmentRemainingTotal
        ))
        lines.append(AssetBreakdownLine(
            id: "available-total",
            label: "可动用资金",
            amount: cashPoolAvailable,
            style: .total
        ))
        return lines
    }

    private func totalAssetsLines() -> [AssetBreakdownLine] {
        var lines = activeCashPoolItems
            .filter { !$0.kind.isNegative }
            .map { item in
                AssetBreakdownLine(
                    id: "asset-\(item.id.uuidString)",
                    label: item.name,
                    detail: item.kind.displayName,
                    amount: item.amount
                )
            }
        lines.append(AssetBreakdownLine(
            id: "transaction-delta",
            label: "记账增减",
            detail: "自安装以来所有记账对现金的累计影响",
            amount: cashPoolTransactionDelta,
            drillsIntoCashImpact: true
        ))
        if overdraftLiability > 0 {
            // 流动资金已为负，总资产按 0 计；差额转到负债那边，这里补一行让加法闭合。
            lines.append(AssetBreakdownLine(
                id: "overdraft-transfer",
                label: "超支部分转记负债",
                detail: "资金已花超，总资产按 0 计，缺口计入总负债",
                amount: overdraftLiability
            ))
        }
        lines.append(AssetBreakdownLine(
            id: "assets-total",
            label: "总资产",
            amount: totalAssets,
            style: .total
        ))
        return lines
    }

    private func totalLiabilitiesLines() -> [AssetBreakdownLine] {
        var lines = activeCashPoolItems
            .filter { $0.kind.isNegative }
            .map { item in
                AssetBreakdownLine(
                    id: "liability-\(item.id.uuidString)",
                    label: item.name,
                    detail: item.kind.displayName,
                    amount: item.amount
                )
            }
        lines.append(AssetBreakdownLine(
            id: "installment-remaining",
            label: "分期待还",
            detail: installmentDetail,
            amount: installmentRemainingTotal
        ))
        if overdraftLiability > 0 {
            lines.append(AssetBreakdownLine(
                id: "overdraft",
                label: "现金超支",
                detail: "记账支出超过登记的可用资金，超出部分计为负债",
                amount: overdraftLiability
            ))
        }
        lines.append(AssetBreakdownLine(
            id: "liabilities-total",
            label: "总负债",
            amount: totalLiabilities,
            style: .total
        ))
        return lines
    }

    private var installmentDetail: String? {
        activeInstallmentBills.isEmpty ? nil : "\(activeInstallmentBills.count) 笔未还清"
    }
}
