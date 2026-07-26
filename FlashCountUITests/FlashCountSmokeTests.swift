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

    func testBackTapSetupIsDiscoverableFromSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "true"]
        app.launch()

        openLedgerMoreItem(app, identifier: "ledger.settings")

        let backTapSetup = app.buttons["settings.backTapSetup"]
        XCTAssertTrue(backTapSetup.waitForExistence(timeout: 5))
        backTapSetup.tap()

        XCTAssertTrue(app.navigationBars["轻点背面"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["backTapSetup.shortcutsLink"].waitForExistence(timeout: 5)
        )
    }

    func testDataHealthCenterScansFromSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "true"]
        app.launch()

        openLedgerMoreItem(app, identifier: "ledger.settings")

        let dataHealth = app.buttons["settings.dataHealth"]
        for _ in 0..<5 where !dataHealth.exists {
            app.swipeUp()
        }
        XCTAssertTrue(dataHealth.waitForExistence(timeout: 5))
        dataHealth.tap()

        XCTAssertTrue(app.navigationBars["本地数据健康中心"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["检查结果"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dataHealth.rescan"].waitForExistence(timeout: 5))
    }

    func testActionCenterShowsLocalItemsAndRoutesToReminderPage() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-hasCompletedOnboarding", "true",
            "-uiTestActionCenter"
        ]
        app.launch()

        let actionCenter = app.buttons["ledger.actionCenter"]
        XCTAssertTrue(actionCenter.waitForExistence(timeout: 5))
        actionCenter.tap()

        XCTAssertTrue(app.navigationBars["本地行动中心"].waitForExistence(timeout: 5))
        let sectionIdentifiers = [
            "actionCenter.section.budgetOverrun",
            "actionCenter.section.recurringDebit",
            "actionCenter.section.installmentDue",
            "actionCenter.section.recurringSuggestion",
            "actionCenter.section.incompleteReminder"
        ]
        for identifier in sectionIdentifiers {
            XCTAssertTrue(
                app.descendants(matching: .any)[identifier].waitForExistence(timeout: 5),
                "行动中心应显示分组：\(identifier)"
            )
        }

        let reminderItem = app.buttons["actionCenter.item.incompleteReminder"]
        XCTAssertTrue(reminderItem.waitForExistence(timeout: 5))
        reminderItem.tap()
        XCTAssertTrue(app.navigationBars["提醒事项"].waitForExistence(timeout: 5))

        let closeReminder = app.navigationBars["提醒事项"].buttons["关闭"]
        XCTAssertTrue(closeReminder.waitForExistence(timeout: 5))
        closeReminder.tap()
        XCTAssertTrue(app.navigationBars["本地行动中心"].waitForExistence(timeout: 5))
    }

    func testLedgerBatchActionsStayAboveMainTabBar() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "true"]
        app.launch()

        let ledgerTab = app.buttons["mainTab.ledger"]
        XCTAssertTrue(ledgerTab.waitForExistence(timeout: 5))
        openLedgerMoreItem(app, identifier: "ledger.batchSelect")

        let batchDone = app.buttons["ledger.batchDone"]
        XCTAssertTrue(batchDone.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(
            batchDone.frame.maxY,
            ledgerTab.frame.minY,
            "账本批量操作栏不应与主标签栏重叠"
        )
    }

    func testMainTabBarStaysAvailableAfterIdle() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-hasCompletedOnboarding", "true",
            "-visualReviewTab", "3",
            "-uiTestTabBarIdle"
        ]
        app.launch()

        let reportTab = app.buttons["mainTab.report"]
        let weekly = app.buttons["report.period.weekly"]
        XCTAssertTrue(reportTab.waitForExistence(timeout: 5))
        XCTAssertTrue(weekly.waitForExistence(timeout: 5))
        sleep(3)
        XCTAssertTrue(
            reportTab.waitForExistence(timeout: 3),
            "底部标签栏应始终提供主导航路径"
        )

        weekly.tap()
        XCTAssertTrue(
            reportTab.waitForExistence(timeout: 2),
            "页面交互后主导航仍应存在"
        )
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

    func testQuickEntrySuccessPageKeepsBothActionsAvailable() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "true", "-visualQuickEntryReview"]
        app.launch()

        let oneKey = app.buttons["quickEntry.key.1"]
        let save = app.buttons["quickEntry.save"]
        XCTAssertTrue(oneKey.waitForExistence(timeout: 5))
        oneKey.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        save.tap()

        let success = app.staticTexts["记账成功！"]
        XCTAssertTrue(success.waitForExistence(timeout: 5))
        sleep(3)
        XCTAssertTrue(success.exists)
        XCTAssertTrue(app.buttons["再记一笔"].exists)
        XCTAssertTrue(app.buttons["完成"].exists)
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

    func testReportContentStopsAboveMainTabBar() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-hasCompletedOnboarding", "true",
            "-visualReviewTab", "3",
            "-uiTestReportLayout"
        ]
        app.launch()

        let scrollView = app.scrollViews["report.scroll"]
        let contentEnd = app.otherElements["report.contentEnd"]
        let reportTab = app.buttons["mainTab.report"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
        XCTAssertTrue(contentEnd.waitForExistence(timeout: 5))
        XCTAssertTrue(reportTab.waitForExistence(timeout: 5))

        for _ in 0..<12 where contentEnd.frame.maxY > reportTab.frame.minY {
            scrollView.swipeUp()
        }

        XCTAssertLessThanOrEqual(
            contentEnd.frame.maxY,
            reportTab.frame.minY,
            "报表内容末尾不应被主标签栏覆盖"
        )
    }

    func testForegroundReportNotificationPresentsMatchingReport() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-hasCompletedOnboarding", "true",
            "-uiTestForegroundReport", "monthly"
        ]
        app.launch()

        let close = app.buttons["report.foreground.close"]
        let monthly = app.buttons["report.period.monthly"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(monthly.waitForExistence(timeout: 5))
        XCTAssertTrue(monthly.isSelected)
        XCTAssertTrue(app.staticTexts["report.range"].waitForExistence(timeout: 5))

        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["mainTab.ledger"].isSelected)
    }

    func testForegroundReportWaitsForQuickEntryToDismiss() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-hasCompletedOnboarding", "true",
            "-uiTestForegroundReport", "daily",
            "-uiTestForegroundReportWhileQuickEntry"
        ]
        app.launch()

        let quickEntry = app.navigationBars["记一笔"]
        let closeReport = app.buttons["report.foreground.close"]
        XCTAssertTrue(quickEntry.waitForExistence(timeout: 5))
        XCTAssertFalse(closeReport.exists)

        app.buttons["取消"].tap()

        XCTAssertTrue(closeReport.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["report.period.daily"].isSelected)
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

    func testReportTopCategoryDrillDownListsMatchingTransactions() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-hasCompletedOnboarding", "true",
            "-uiTestReportLayout",
            "-visualReviewTab", "3"
        ]
        app.launch()

        let topCategory = app.buttons["report.topCategory.0"]
        XCTAssertTrue(topCategory.waitForExistence(timeout: 10), "报表应展示消费 Top 5 分类行")
        // 屏幕外元素的 exists 同样为真，必须按可点击性判断是否还需要滚动。
        for _ in 0..<8 where !topCategory.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(topCategory.isHittable)

        let cards = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        cards.name = "report-top-categories"
        cards.lifetime = .keepAlways
        add(cards)

        topCategory.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["report.drillDown.summary"].waitForExistence(timeout: 5),
            "点击分类应打开该分类的支出明细"
        )

        let detail = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        detail.name = "report-drill-down"
        detail.lifetime = .keepAlways
        add(detail)

        let close = app.buttons["report.drillDown.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(app.navigationBars["报表"].waitForExistence(timeout: 5))
    }

    /// 账本工具栏的次级动作收在「更多」菜单里；先展开菜单再点目标项。
    private func openLedgerMoreItem(_ app: XCUIApplication, identifier: String) {
        let more = app.buttons["ledger.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()

        let item = app.buttons[identifier]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
    }
}
