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

    func testMainTabBarSelectionKeepsControlsAligned() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26,
            "Liquid Glass 标签栏仅在 iOS 26 及以上启用"
        )

        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "true"]
        app.launch()

        let identifiers = [
            "mainTab.ledger",
            "mainTab.budget",
            "mainTab.quickEntry",
            "mainTab.report",
            "mainTab.assets"
        ]
        let controls = identifiers.map { app.buttons[$0] }
        controls.forEach {
            XCTAssertTrue($0.waitForExistence(timeout: 5), "底部标签按钮应存在：\($0.identifier)")
        }

        let initialFrames = controls.map(\.frame)
        let referenceFrame = initialFrames[0]
        for frame in initialFrames.dropFirst() {
            XCTAssertEqual(frame.midY, referenceFrame.midY, accuracy: 1)
            XCTAssertEqual(frame.height, referenceFrame.height, accuracy: 1)
        }

        let navigationTabs = [controls[0], controls[1], controls[3], controls[4]]
        XCTAssertEqual(navigationTabs.filter(\.isSelected).count, 1)

        for target in navigationTabs.dropFirst() {
            target.tap()
            let selected = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "selected == true"),
                object: target
            )
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 3), .completed)
            XCTAssertEqual(navigationTabs.filter(\.isSelected).count, 1)

            let framesSettled = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    zip(controls, initialFrames).allSatisfy { pair in
                        let (control, initialFrame) = pair
                        let currentFrame = control.frame
                        return abs(currentFrame.minX - initialFrame.minX) <= 1
                            && abs(currentFrame.minY - initialFrame.minY) <= 1
                            && abs(currentFrame.width - initialFrame.width) <= 1
                            && abs(currentFrame.height - initialFrame.height) <= 1
                    }
                },
                object: nil
            )
            XCTAssertEqual(XCTWaiter.wait(for: [framesSettled], timeout: 2), .completed)

            for (control, initialFrame) in zip(controls, initialFrames) {
                let currentFrame = control.frame
                XCTAssertEqual(currentFrame.minX, initialFrame.minX, accuracy: 1)
                XCTAssertEqual(currentFrame.minY, initialFrame.minY, accuracy: 1)
                XCTAssertEqual(currentFrame.width, initialFrame.width, accuracy: 1)
                XCTAssertEqual(currentFrame.height, initialFrame.height, accuracy: 1)
            }
        }
    }

    func testQuickEntryNumberKeyEnablesSave() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "true", "-visualQuickEntryReview"]
        app.launch()

        let oneKey = app.buttons["quickEntry.key.1"]
        let amount = app.staticTexts["quickEntry.amount"]
        let save = app.buttons["quickEntry.save"]
        let categoryControls = app.buttons["展开全部分类"]

        XCTAssertTrue(oneKey.waitForExistence(timeout: 5))
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertTrue(categoryControls.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(
            categoryControls.frame.maxY,
            oneKey.frame.minY,
            "底部玻璃键盘不应覆盖分类控制区"
        )
        XCTAssertFalse(save.isEnabled)

        oneKey.tap()

        XCTAssertEqual(amount.label, "1")
        XCTAssertTrue(save.isEnabled)
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
