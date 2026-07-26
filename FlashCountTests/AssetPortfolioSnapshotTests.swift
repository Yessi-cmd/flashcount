import XCTest
import SwiftData
@testable import FlashCount

/// 净资产口径此前只存在于视图里的 private struct，从未被任何测试覆盖过——
/// 而它是全 App 最容易算错的一段数学。
@MainActor
final class AssetPortfolioSnapshotTests: XCTestCase {
    func testNetWorthCombinesCashPoolLedgerDeltaAndLiabilities() {
        let snapshot = AssetPortfolioSnapshot(
            cashPoolItems: [
                CashPoolItem(name: "现金", kind: .cash, amount: 10_000),
                CashPoolItem(name: "可赎回理财", kind: .flexibleInvestment, amount: 5_000),
                CashPoolItem(name: "朋友借款", kind: .liability, amount: 2_000)
            ],
            cashPoolTransactionDelta: -1_000,
            installmentBills: [bill(total: 600, count: 3, paid: 1)]
        )

        XCTAssertEqual(snapshot.cashPoolManualTotal, 13_000, "资金净额按签名金额求和")
        XCTAssertEqual(snapshot.installmentRemainingTotal, 400)
        XCTAssertEqual(snapshot.totalAssets, 14_000, "流动资产为正项加上记账增减")
        XCTAssertEqual(snapshot.totalLiabilities, 2_400, "手工负债加上分期待还")
        XCTAssertEqual(snapshot.netWorth, 11_600)
        XCTAssertEqual(snapshot.cashPoolAvailable, 11_600)
    }

    /// 记账累计超过手工登记的余额时，流动资金转负。
    /// 总资产不能显示成负数——超出的部分应整体记为负债。
    func testOverdrawnLiquidFundsBecomeLiabilityInsteadOfNegativeAssets() {
        let snapshot = AssetPortfolioSnapshot(
            cashPoolItems: [CashPoolItem(name: "现金", kind: .cash, amount: 500)],
            cashPoolTransactionDelta: -1_200
        )

        XCTAssertEqual(snapshot.totalAssets, 0)
        XCTAssertEqual(snapshot.totalLiabilities, 700)
        XCTAssertEqual(snapshot.netWorth, -700)
        XCTAssertEqual(snapshot.cashPoolAvailable, -700)
    }

    func testArchivedRecordsAreExcludedEverywhere() {
        let archivedItem = CashPoolItem(name: "旧账户", kind: .cash, amount: 9_999)
        archivedItem.isArchived = true
        let archivedBill = bill(total: 1_000, count: 2, paid: 0)
        archivedBill.isArchived = true
        let archivedGoal = SavingsGoal(name: "旧目标", targetAmount: 5_000, currentAmount: 1_000)
        archivedGoal.isArchived = true

        let snapshot = AssetPortfolioSnapshot(
            cashPoolItems: [CashPoolItem(name: "现金", kind: .cash, amount: 100), archivedItem],
            savingsGoals: [SavingsGoal(name: "应急金", targetAmount: 3_000, currentAmount: 500), archivedGoal],
            installmentBills: [archivedBill]
        )

        XCTAssertEqual(snapshot.totalAssets, 100)
        XCTAssertEqual(snapshot.totalLiabilities, 0)
        XCTAssertEqual(snapshot.savingsCurrentTotal, 500)
        XCTAssertEqual(snapshot.savingsTargetTotal, 3_000)
        XCTAssertEqual(snapshot.activeCashPoolItems.count, 1)
    }

    /// 口径决策：储蓄目标的钱本来就躺在现金里，实物资产不流动——
    /// 两者都不并入净资产，否则会重复计算。
    func testSavingsAndPhysicalAssetsStayOutOfNetWorth() {
        let phone = PhysicalAsset(
            name: "手机",
            category: .phone,
            purchasePrice: 8_000,
            purchaseDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let snapshot = AssetPortfolioSnapshot(
            physicalAssets: [phone],
            cashPoolItems: [CashPoolItem(name: "现金", kind: .cash, amount: 1_000)],
            savingsGoals: [SavingsGoal(name: "应急金", targetAmount: 5_000, currentAmount: 2_000)]
        )

        XCTAssertEqual(snapshot.netWorth, 1_000, "净资产只反映资金池")
        XCTAssertGreaterThan(snapshot.physicalTotalValue, 0, "实物资产仍单独统计")
        XCTAssertEqual(snapshot.savingsCurrentTotal, 2_000)
    }

    /// 实物资产展示的是每天的合计成本，而不是各件的平均值。
    func testPhysicalDailyCostIsSummedNotAveraged() {
        let purchaseDate = Calendar.current.date(byAdding: .day, value: -100, to: Date()) ?? Date()
        let first = PhysicalAsset(name: "手机", category: .phone, purchasePrice: 1_000,
                                  purchaseDate: purchaseDate, salvageValue: 0)
        let second = PhysicalAsset(name: "耳机", category: .headphone, purchasePrice: 500,
                                   purchaseDate: purchaseDate, salvageValue: 0)

        let snapshot = AssetPortfolioSnapshot(physicalAssets: [first, second])

        XCTAssertEqual(snapshot.physicalDailyCostTotal, first.dailyCost + second.dailyCost)
        XCTAssertEqual(snapshot.physicalPurchaseTotal, 1_500)
    }

    func testEmptyPortfolioReportsEmpty() {
        XCTAssertTrue(AssetPortfolioSnapshot().isEmpty)
        XCTAssertEqual(AssetPortfolioSnapshot().netWorth, 0)
        XCTAssertFalse(
            AssetPortfolioSnapshot(cashPoolItems: [CashPoolItem(name: "现金", kind: .cash, amount: 1)]).isEmpty
        )
    }

    private func bill(total: Decimal, count: Int, paid: Int) -> InstallmentBill {
        InstallmentBill(
            name: "分期",
            totalAmount: total,
            installmentCount: count,
            paidInstallments: paid,
            repaymentDay: 10,
            firstRepaymentDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
