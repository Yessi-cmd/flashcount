import XCTest
@testable import FlashCount

/// 折旧、日均成本、回本进度全部随「今天是哪天」变化。
/// 参照时刻可注入之后，这些曲线才能被确定性地钉住。
@MainActor
final class PhysicalAssetTests: XCTestCase {
    private let purchaseDate = Date(timeIntervalSince1970: 1_700_000_000)

    func testStraightLineDepreciationBottomsOutAtSalvageValue() throws {
        // 手机默认折旧率 0.25，即四年（1460 天）折完可折旧金额。
        let phone = PhysicalAsset(
            name: "手机",
            category: .phone,
            purchasePrice: 10_000,
            purchaseDate: purchaseDate,
            salvageValue: 2_000
        )

        let afterOneYear = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: 365, to: purchaseDate)
        )
        // 8000 可折旧 ÷ 1460 天 × 365 天 = 2000，估值应为 10000 − 2000。
        XCTAssertEqual(phone.currentValue(asOf: afterOneYear), 8_000)

        let afterTenYears = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: 3_650, to: purchaseDate)
        )
        XCTAssertEqual(phone.currentValue(asOf: afterTenYears), 2_000, "估值不得跌破预估残值")
    }

    func testDailyCostFallsAsTheAssetIsHeldLonger() throws {
        let laptop = PhysicalAsset(
            name: "笔记本",
            category: .laptop,
            purchasePrice: 12_000,
            purchaseDate: purchaseDate,
            salvageValue: 2_000
        )

        let day100 = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 100, to: purchaseDate))
        let day200 = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 200, to: purchaseDate))

        XCTAssertEqual(laptop.dailyCost(asOf: day100), 100)
        XCTAssertEqual(laptop.dailyCost(asOf: day200), 50)
        XCTAssertLessThan(laptop.dailyCost(asOf: day200), laptop.dailyCost(asOf: day100))
    }

    func testProgressTowardTargetDailyCostSaturatesAtOne() throws {
        let asset = PhysicalAsset(
            name: "相机",
            category: .camera,
            purchasePrice: 6_000,
            purchaseDate: purchaseDate,
            salvageValue: 1_000,
            targetDailyCost: 10 // 5000 ÷ 10 = 500 天回本
        )

        let day250 = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 250, to: purchaseDate))
        let day600 = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 600, to: purchaseDate))

        XCTAssertEqual(asset.progressToTarget(asOf: day250), 0.5, accuracy: 0.01)
        XCTAssertEqual(asset.daysToTarget(asOf: day250), 250)
        XCTAssertEqual(asset.progressToTarget(asOf: day600), 1)
        XCTAssertEqual(asset.daysToTarget(asOf: day600), 0, "已达目标时不应再报剩余天数")
    }

    func testDaysToTargetRoundsFractionalTargetDaysUp() throws {
        let asset = PhysicalAsset(
            name: "相机",
            category: .camera,
            purchasePrice: 6_000,
            purchaseDate: purchaseDate,
            salvageValue: 1_000,
            targetDailyCost: 300 // 5000 ÷ 300 = 16.666...，需要完整的第 17 天
        )
        let dayOne = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: purchaseDate))

        XCTAssertEqual(asset.daysToTarget(asOf: dayOne), 16)
    }

    /// 出售后持有天数冻结在售出日，估值也不再随时间下滑。
    func testSoldAssetFreezesItsHoldingPeriod() throws {
        let asset = PhysicalAsset(
            name: "平板",
            category: .tablet,
            purchasePrice: 5_000,
            purchaseDate: purchaseDate,
            salvageValue: 1_000
        )
        let soldDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 200, to: purchaseDate))
        asset.soldPrice = 3_000
        asset.soldDate = soldDate

        let muchLater = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 2_000, to: purchaseDate))
        XCTAssertEqual(asset.daysHeld(asOf: muchLater), 200)
        XCTAssertEqual(asset.dailyCost(asOf: muchLater), 20)
    }

    /// 持有净成本的方向：花掉的钱是正数，升值才是负数。
    func testNetHoldingCostIsPositiveWhenMoneyWasSpent() throws {
        let asset = PhysicalAsset(
            name: "手机",
            category: .phone,
            purchasePrice: 8_000,
            purchaseDate: purchaseDate
        )
        XCTAssertNil(asset.netHoldingCost, "未出售时没有净成本")

        asset.soldPrice = 3_000
        asset.soldDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 500, to: purchaseDate))
        XCTAssertEqual(asset.netHoldingCost, 5_000, "买 8000 卖 3000，净花掉 5000")
        XCTAssertEqual(asset.actualDailyCost, 10)

        asset.soldPrice = 9_000
        XCTAssertEqual(asset.netHoldingCost, -1_000, "卖得比买价高时为负数，即净赚")
    }
}
