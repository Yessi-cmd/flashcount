import XCTest
@testable import FlashCount

/// 下钻明细存在的意义就是让用户自己核对，因此最重要的性质只有一条：
/// 明细行加起来必须等于卡片上那个数字。任何一处漏项都会让下钻比不下钻更糟。
@MainActor
final class AssetBreakdownTests: XCTestCase {
    func testEveryBreakdownSumsToItsHeadlineNumber() {
        for snapshot in [healthySnapshot(), overdrawnSnapshot(), AssetPortfolioSnapshot()] {
            for kind in AssetBreakdownKind.allCases {
                let lines = snapshot.breakdown(kind)
                let total = try? XCTUnwrap(lines.last)
                XCTAssertEqual(total?.style, .total, "\(kind.title) 的最后一行应是合计")

                let itemsSum = lines
                    .filter { $0.style == .item }
                    .reduce(Decimal.zero) { $0 + $1.amount }
                XCTAssertEqual(itemsSum, total?.amount, "\(kind.title) 的构成项之和必须等于合计")
            }
        }
    }

    func testAvailableFundsBreakdownSpellsOutTheHiddenFormula() {
        let lines = healthySnapshot().breakdown(.availableFunds)
        let labels = lines.map(\.label)

        XCTAssertEqual(labels, ["现金", "可赎回理财", "朋友借款", "资金净额", "记账增减", "分期待还", "可动用资金"])
        XCTAssertEqual(lines.first { $0.id == "manual-subtotal" }?.amount, 13_000)
        XCTAssertEqual(lines.first { $0.id == "transaction-delta" }?.amount, -1_000)
        XCTAssertEqual(lines.first { $0.id == "installment-remaining" }?.amount, -400, "分期待还在此处是减项")
        XCTAssertEqual(lines.last?.amount, 11_600)
    }

    /// 「资金净额」有自己的下钻口径：只是手工登记的资金项正负相抵。
    /// 它以前借用「可动用资金」的明细，于是点开看到的标题和数字都不是自己那一格。
    func testNetFundsBreakdownExplainsOnlyTheManualItems() {
        let lines = healthySnapshot().breakdown(.netFunds)

        XCTAssertEqual(lines.map(\.label), ["现金", "可赎回理财", "朋友借款", "资金净额"])
        XCTAssertEqual(lines.last?.amount, 13_000)
        XCTAssertEqual(AssetBreakdownKind.netFunds.title, "资金净额")
        XCTAssertNil(
            lines.first { $0.id == "transaction-delta" },
            "资金净额不含记账增减——那是可动用资金才要解释的部分"
        )
        XCTAssertNil(lines.first { $0.id == "installment-remaining" }, "资金净额不含分期待还")
        XCTAssertTrue(lines.allSatisfy { !$0.drillsIntoCashImpact })
    }

    /// 「记账增减」是唯一一个用户无从查证的分量，必须能继续下钻。
    func testOnlyTheLedgerDeltaOffersASecondLevelDrill() {
        let lines = healthySnapshot().breakdown(.availableFunds)
        XCTAssertEqual(lines.filter(\.drillsIntoCashImpact).map(\.id), ["transaction-delta"])
    }

    /// 花超之后总资产被钳到 0，缺口翻到负债那边。
    /// 这条规则以前完全不可见，用户只会看到总负债莫名多出一截。
    func testOverdraftIsExplainedOnBothSides() {
        let snapshot = overdrawnSnapshot()
        XCTAssertEqual(snapshot.totalAssets, 0)
        XCTAssertEqual(snapshot.overdraftLiability, 700)

        let assetLines = snapshot.breakdown(.totalAssets)
        XCTAssertNotNil(assetLines.first { $0.id == "overdraft-transfer" }, "总资产侧应说明缺口去了哪里")
        XCTAssertEqual(assetLines.last?.amount, 0)

        let liabilityLines = snapshot.breakdown(.totalLiabilities)
        let overdraft = try? XCTUnwrap(liabilityLines.first { $0.id == "overdraft" })
        XCTAssertEqual(overdraft?.amount, 700)
        XCTAssertEqual(liabilityLines.last?.amount, snapshot.totalLiabilities)
    }

    func testHealthyPortfolioShowsNoOverdraftLines() {
        let snapshot = healthySnapshot()
        XCTAssertEqual(snapshot.overdraftLiability, 0)
        XCTAssertNil(snapshot.breakdown(.totalAssets).first { $0.id == "overdraft-transfer" })
        XCTAssertNil(snapshot.breakdown(.totalLiabilities).first { $0.id == "overdraft" })
    }

    // MARK: - 固定样本

    private func healthySnapshot() -> AssetPortfolioSnapshot {
        AssetPortfolioSnapshot(
            cashPoolItems: [
                CashPoolItem(name: "现金", kind: .cash, amount: 10_000, sortOrder: 0),
                CashPoolItem(name: "可赎回理财", kind: .flexibleInvestment, amount: 5_000, sortOrder: 1),
                CashPoolItem(name: "朋友借款", kind: .liability, amount: 2_000, sortOrder: 2)
            ],
            cashPoolTransactionDelta: -1_000,
            installmentBills: [
                InstallmentBill(
                    name: "分期",
                    totalAmount: 600,
                    installmentCount: 3,
                    paidInstallments: 1,
                    repaymentDay: 10,
                    firstRepaymentDate: Date(timeIntervalSince1970: 1_700_000_000)
                )
            ]
        )
    }

    private func overdrawnSnapshot() -> AssetPortfolioSnapshot {
        AssetPortfolioSnapshot(
            cashPoolItems: [CashPoolItem(name: "现金", kind: .cash, amount: 500)],
            cashPoolTransactionDelta: -1_200
        )
    }
}
