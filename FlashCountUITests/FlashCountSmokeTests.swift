import XCTest

final class FlashCountSmokeTests: XCTestCase {
    func testOnboardingCompletesOnlyAfterStartButton() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "false"]
        app.launch()

        let start = app.buttons["开始使用"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(app.buttons["快速记账"].waitForExistence(timeout: 5))
    }

    func testQuickEntryOpensFromMainTab() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "true"]
        app.launch()

        let quickEntry = app.buttons["快速记账"]
        XCTAssertTrue(quickEntry.waitForExistence(timeout: 5))
        quickEntry.tap()
        XCTAssertTrue(app.navigationBars["记一笔"].waitForExistence(timeout: 5))
    }

    func testQuickEntryCategoryWheelOpensAndCancelsWithoutChangingTheForm() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "true"]
        app.launch()

        let quickEntry = app.buttons["快速记账"]
        XCTAssertTrue(quickEntry.waitForExistence(timeout: 5))
        quickEntry.tap()

        let dining = app.buttons["餐饮，包含小类"]
        XCTAssertTrue(dining.waitForExistence(timeout: 5))
        dining.tap()
        XCTAssertTrue(app.otherElements["categoryWheelOverlay"].waitForExistence(timeout: 3))

        let overlay = app.otherElements.matching(identifier: "categoryWheelOverlay").firstMatch
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.90)).tap()
        XCTAssertTrue(overlay.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["记一笔"].exists)
    }

    func testReportShowsCurrentRangeAndNavigatesToPreviousPeriod() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "true"]
        app.launch()

        let reportTab = app.buttons["报表"]
        XCTAssertTrue(reportTab.waitForExistence(timeout: 5))
        reportTab.tap()

        XCTAssertTrue(app.staticTexts["report.range"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["report.nextPeriod"].isEnabled)
        app.buttons["report.previousPeriod"].tap()
        XCTAssertTrue(app.buttons["report.nextPeriod"].isEnabled)
    }

    func testReportCanSwitchToPayCyclePeriod() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "true", "-payday", "25"]
        app.launch()

        app.buttons["报表"].tap()
        let payCycle = app.buttons["report.period.payCycle"]
        XCTAssertTrue(payCycle.waitForExistence(timeout: 5))
        payCycle.tap()

        XCTAssertTrue(app.staticTexts["report.range"].waitForExistence(timeout: 5))
        XCTAssertTrue(payCycle.isSelected)
    }

    func testQuickEntryCategoryWheelImmediatelyAcceptsSubcategorySelection() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "true"]
        app.launch()

        let quickEntry = app.buttons["快速记账"]
        XCTAssertTrue(quickEntry.waitForExistence(timeout: 5))
        quickEntry.tap()

        let dining = app.buttons["餐饮，包含小类"]
        XCTAssertTrue(dining.waitForExistence(timeout: 5))
        let meal = app.staticTexts["正餐"]

        dining.tap()
        meal.tap()

        XCTAssertTrue(app.navigationBars["记一笔"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["categoryWheelOverlay"].exists)
        XCTAssertEqual(dining.value as? String, "已选中：餐饮 · 正餐")
    }
}
