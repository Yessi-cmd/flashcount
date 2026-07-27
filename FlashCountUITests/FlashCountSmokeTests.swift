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

    /// 保存后不再要求多按一次「完成」：sheet 自己关掉，
    /// 确认和撤销留在主界面的提示条上。
    func testQuickEntrySaveClosesSheetAndOffersUndo() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "true"]
        app.launch()

        let quickEntry = app.buttons["快速记账"]
        XCTAssertTrue(quickEntry.waitForExistence(timeout: 5))
        quickEntry.tap()

        let oneKey = app.buttons["quickEntry.key.1"]
        XCTAssertTrue(oneKey.waitForExistence(timeout: 5))
        oneKey.tap()

        let save = app.buttons["quickEntry.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        save.tap()

        XCTAssertTrue(
            app.navigationBars["记一笔"].waitForNonExistence(timeout: 5),
            "保存后记账页应自动关闭"
        )

        let undo = app.buttons["quickEntry.undoSaved"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3), "提示条应提供撤销")
        undo.tap()
        XCTAssertTrue(undo.waitForNonExistence(timeout: 3), "撤销后提示条应收起")
    }

    /// 未选中的一级分类点一下就选中。出行有小类，过去点它只会打开圆盘，
    /// 最常走的那条路被硬性拉成两次点击。
    func testTappingUnselectedCategoryTileSelectsInsteadOfOpeningWheel() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "true"]
        app.launch()

        let transport = openQuickEntryAndRevealTransportTile(app)
        XCTAssertEqual(transport.value as? String, "未选中", "出行不应是默认选中项")

        // 断言落在分类区下方那行「已选 …」上：选中会收起「全部分类」，
        // 回头重新展开去读格子状态会撞上收起动画，测出来是不稳定的。
        let selectionBefore = currentSelectionLabel(app)
        transport.tap()

        XCTAssertFalse(
            app.otherElements["categoryWheelOverlay"].waitForExistence(timeout: 2),
            "点按未选中的一级分类不应弹圆盘"
        )
        XCTAssertNotEqual(
            currentSelectionLabel(app),
            selectionBefore,
            "点按后选中项应换成出行这一组"
        )
    }

    /// 圆盘的入口：分类区下方那颗看得见的「换小类」按钮。
    /// 单点直接选中之后，选具体小类必须有一个明确的去处。
    func testChangeSubcategoryButtonOpensWheel() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "true"]
        app.launch()

        openQuickEntryAndRevealTransportTile(app).tap()

        let change = app.buttons["quickEntry.changeSubcategory"]
        XCTAssertTrue(change.waitForExistence(timeout: 5), "选中带小类的分类后应出现「换小类」")
        change.tap()

        XCTAssertTrue(
            app.otherElements["categoryWheelOverlay"].waitForExistence(timeout: 3),
            "「换小类」应打开分类圆盘"
        )
    }

    /// 分类区下方那行「已选 …」的文案，用来判断当前选中项。
    private func currentSelectionLabel(_ app: XCUIApplication) -> String {
        let label = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "已选 "))
            .firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: 5), "分类区应显示当前选中项")
        return label.label
    }

    /// 「常用」只列有近期交易的分类，出行通常要展开「全部分类」才出现。
    /// 选它而不是餐饮，是因为餐饮是默认选中项，测不出「未选中→点一下就选中」。
    @discardableResult
    private func openQuickEntryAndRevealTransportTile(_ app: XCUIApplication) -> XCUIElement {
        let quickEntry = app.buttons["快速记账"]
        XCTAssertTrue(quickEntry.waitForExistence(timeout: 5))
        quickEntry.tap()
        return revealTransportTile(app)
    }

    /// 选中动作会收起「全部分类」，所以每次读取状态前都要重新展开。
    @discardableResult
    private func revealTransportTile(_ app: XCUIApplication) -> XCUIElement {
        let transport = app.buttons["category.tile.出行"].firstMatch
        if !transport.waitForExistence(timeout: 2) {
            let expand = app.buttons["展开全部分类"]
            XCTAssertTrue(expand.waitForExistence(timeout: 5))
            expand.tap()
        }
        XCTAssertTrue(transport.waitForExistence(timeout: 5), "出行分类应可见")

        // 展开后的「全部分类」落在底部键盘下方（滚动区自己可以滚上来）。
        // XCUITest 仍会把它报成 hittable，但点下去落在键盘上，所以先滚进可视区。
        let keypadTop = app.buttons["quickEntry.key.7"].frame.minY
        var attempts = 0
        while transport.frame.maxY > keypadTop, attempts < 5 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertLessThanOrEqual(
            transport.frame.maxY,
            app.buttons["quickEntry.key.7"].frame.minY,
            "出行格子应滚到键盘上方再点"
        )
        return transport
    }

    private func openLedgerMoreItem(_ app: XCUIApplication, identifier: String) {
        let more = app.buttons["ledger.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        tapDirectly(more)

        let item = app.buttons[identifier]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
    }

    /// 按坐标点，绕开 XCUITest 的 scroll-to-visible。
    ///
    /// 导航栏按钮本来就完整可见，但 `tap()` 会先尝试 AX 的
    /// `kAXScrollToVisibleAction`，在部分 Xcode/运行时组合上它对工具栏元素返回
    /// `kAXErrorCannotComplete`，于是点击整个失败——这与被测行为无关。
    private func tapDirectly(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
