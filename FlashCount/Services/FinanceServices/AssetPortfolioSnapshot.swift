import Foundation

/// 资产页的一次性汇总。
///
/// 从视图里抽出来有两个原因：一是每个卡片不必再各自 filter/reduce 同一批数据；
/// 二是净资产口径是全 App 最绕的一段金钱数学（负余额要翻成负债、分期待还既压
/// 可动用资金又计入负债），留在 View 的 private struct 里就永远测不到。
///
/// 口径：净资产只统计资金池与负债。实物资产不流动、储蓄目标的钱本就躺在现金里，
/// 两者都单独展示，不并入净资产，以免重复计算。
struct AssetPortfolioSnapshot {
    let activePhysicalAssets: [PhysicalAsset]
    let activeCashPoolItems: [CashPoolItem]
    let activeSavingsGoals: [SavingsGoal]
    let activeInstallmentBills: [InstallmentBill]
    let physicalTotalValue: Decimal
    let physicalPurchaseTotal: Decimal
    /// 各件日均成本之和——用户关心的是「这些东西每天一共花我多少」。
    let physicalDailyCostTotal: Decimal
    let cashPoolManualTotal: Decimal
    let installmentRemainingTotal: Decimal
    let cashPoolAvailable: Decimal
    let totalAssets: Decimal
    let totalLiabilities: Decimal
    let netWorth: Decimal
    let savingsTargetTotal: Decimal
    let savingsCurrentTotal: Decimal

    var isEmpty: Bool {
        activeCashPoolItems.isEmpty
            && activePhysicalAssets.isEmpty
            && activeSavingsGoals.isEmpty
            && activeInstallmentBills.isEmpty
    }

    init(
        physicalAssets: [PhysicalAsset] = [],
        cashPoolItems: [CashPoolItem] = [],
        cashPoolTransactionDelta: Decimal = 0,
        savingsGoals: [SavingsGoal] = [],
        installmentBills: [InstallmentBill] = []
    ) {
        let activePhysicalAssets = physicalAssets.filter { !$0.isArchived }
        physicalTotalValue = activePhysicalAssets.reduce(Decimal(0)) { $0 + $1.currentValue }
        physicalPurchaseTotal = activePhysicalAssets.reduce(Decimal(0)) { $0 + $1.purchasePrice }
        physicalDailyCostTotal = activePhysicalAssets.reduce(Decimal(0)) { $0 + $1.dailyCost }

        let activeCashPoolItems = cashPoolItems.filter { !$0.isArchived }
        var manualTotal: Decimal = 0
        var positiveTotal: Decimal = 0
        var manualLiabilityTotal: Decimal = 0
        for item in activeCashPoolItems {
            manualTotal += item.signedAmount
            if item.kind.isNegative {
                manualLiabilityTotal += item.amount
            } else {
                positiveTotal += item.amount
            }
        }

        let activeInstallmentBills = installmentBills.filter { !$0.isArchived }
        let installmentRemainingTotal = activeInstallmentBills.reduce(Decimal(0)) { $0 + $1.remainingAmount }

        // 记账累计的支出可能把手工登记的余额吃穿。此时净流动资金为负，
        // 应当整体转记为负债，而不是让「总资产」显示成负数。
        let liquidNet = positiveTotal + cashPoolTransactionDelta
        let liquidAssetTotal = max(liquidNet, 0)
        let liquidLiabilityTotal = manualLiabilityTotal + installmentRemainingTotal + max(-liquidNet, 0)

        let activeSavingsGoals = savingsGoals.filter { !$0.isArchived }

        self.activePhysicalAssets = activePhysicalAssets
        self.activeCashPoolItems = activeCashPoolItems
        self.activeSavingsGoals = activeSavingsGoals
        self.activeInstallmentBills = activeInstallmentBills
        self.cashPoolManualTotal = manualTotal
        self.installmentRemainingTotal = installmentRemainingTotal
        self.cashPoolAvailable = manualTotal + cashPoolTransactionDelta - installmentRemainingTotal
        self.totalAssets = liquidAssetTotal
        self.totalLiabilities = liquidLiabilityTotal
        self.netWorth = liquidAssetTotal - liquidLiabilityTotal
        self.savingsTargetTotal = activeSavingsGoals.reduce(Decimal(0)) { $0 + $1.targetAmount }
        self.savingsCurrentTotal = activeSavingsGoals.reduce(Decimal(0)) { $0 + $1.currentAmount }
    }
}
