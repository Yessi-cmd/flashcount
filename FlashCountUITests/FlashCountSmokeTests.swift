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

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.12)).tap()
        XCTAssertTrue(app.navigationBars["记一笔"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["categoryWheelOverlay"].exists)
    }

    func testQuickEntryCategoryWheelSelectionUpdatesTheChosenSubcategory() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "true"]
        app.launch()

        let quickEntry = app.buttons["快速记账"]
        XCTAssertTrue(quickEntry.waitForExistence(timeout: 5))
        quickEntry.tap()

        let dining = app.buttons["餐饮，包含小类"]
        XCTAssertTrue(dining.waitForExistence(timeout: 5))
        dining.tap()

        let meal = app.otherElements["categoryWheelChild-正餐"]
        XCTAssertTrue(meal.waitForExistence(timeout: 3))
        meal.tap()

        XCTAssertTrue(app.navigationBars["记一笔"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["categoryWheelOverlay"].exists)
        XCTAssertEqual(dining.value as? String, "已选中：正餐")
    }
}
