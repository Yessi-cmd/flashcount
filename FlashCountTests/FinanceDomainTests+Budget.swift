import XCTest
import SwiftData
@testable import FlashCount

// MARK: - 发薪周期、预算与日常额度

extension FinanceDomainTests {
    func testPayCycleClampsPaydayToFebruaryEnd() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 2, day: 15))!
        let cycle = PayCycleService.cycle(containing: date, payday: 31, calendar: calendar)

        XCTAssertEqual(calendar.component(.day, from: cycle.start), 31)
        XCTAssertEqual(calendar.component(.month, from: cycle.start), 1)
        XCTAssertEqual(calendar.component(.day, from: cycle.end), 28)
        XCTAssertEqual(calendar.component(.month, from: cycle.end), 2)
    }

    func testBudgetAnalyzerMarksProjectedOverspendAsDanger() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 5))!
        let result = BudgetAnalyzer.analyze(
            budgetLimit: 1_000,
            totalSpent: 500,
            referenceDate: date
        )

        XCTAssertEqual(result.alertLevel, .danger)
        XCTAssertGreaterThan(result.projectedTotal, 1_000)
    }

    func testWeekendBudgetMultiplierRaisesWeekendAllowanceWhileKeepingCycleAllocation() {
        let reference = calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 12))!
        let periodStart = calendar.date(from: DateComponents(year: 2026, month: 7, day: 11))!
        let periodEnd = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))!

        let weekend = BudgetAnalyzer.analyze(
            budgetLimit: 1_000,
            totalSpent: 0,
            referenceDate: reference,
            periodStart: periodStart,
            periodEnd: periodEnd,
            weekendMultiplier: WeekendBudgetMultiplier.oneAndHalf.decimalValue,
            calendar: calendar
        )
        let baseline = BudgetAnalyzer.analyze(
            budgetLimit: 1_000,
            totalSpent: 0,
            referenceDate: reference,
            periodStart: periodStart,
            periodEnd: periodEnd,
            weekendMultiplier: 1,
            calendar: calendar
        )

        XCTAssertTrue(weekend.referenceDateIsWeekend)
        XCTAssertTrue(weekend.isWeekendAllowanceAdjusted)
        XCTAssertEqual(weekend.weekendMultiplier, Decimal(string: "1.5"))
        XCTAssertEqual(weekend.dailyAllowanceTitle, "今日可花")
        XCTAssertEqual(baseline.dailyAllowance, 250)
        XCTAssertEqual(weekend.dailyAllowance, 300)
        XCTAssertEqual(weekend.dailyAllowance * 2 + Decimal(200) * 2, 1_000)

        let reminder = BudgetReminderService.reminder(for: weekend)
        XCTAssertTrue(reminder.isWeekendAllowanceAdjusted)
        XCTAssertFalse(reminder.shortMessage.contains("周末按"))
        XCTAssertFalse(reminder.message.contains("周末按"))

        let doubleWeekend = BudgetAnalyzer.analyze(
            budgetLimit: 1_000,
            totalSpent: 0,
            referenceDate: reference,
            periodStart: periodStart,
            periodEnd: periodEnd,
            weekendMultiplier: WeekendBudgetMultiplier.double.decimalValue,
            calendar: calendar
        )
        XCTAssertEqual(doubleWeekend.weekendMultiplier, 2)
        XCTAssertGreaterThan(doubleWeekend.dailyAllowance, weekend.dailyAllowance)
    }

    func testWeekendBudgetOptionsAreUserSelectable() {
        XCTAssertEqual(WeekendBudgetMultiplier.allCases.map(\.rawValue), [150, 200])
        XCTAssertEqual(WeekendBudgetPreferences.option(for: 150), .oneAndHalf)
        XCTAssertEqual(WeekendBudgetPreferences.option(for: 200), .double)
        XCTAssertEqual(WeekendBudgetPreferences.option(for: 999), .oneAndHalf)
    }

    func testDailyBudgetScopeUsesStableDefaultKeyAndHonorsOverrides() {
        let renamedDining = Category(
            name: "工作日吃饭",
            icon: "fork.knife",
            colorHex: "#000000",
            defaultKey: Category.defaultKey(for: "餐饮", isExpense: true)
        )
        let keylessDining = Category(name: "餐饮", icon: "fork.knife", colorHex: "#000000")
        let transaction = Transaction(amount: 200, category: renamedDining)

        XCTAssertTrue(BudgetScope.includesCategory(renamedDining))
        XCTAssertTrue(BudgetScope.includesInDailyBudget(transaction))
        XCTAssertFalse(BudgetScope.includesCategory(keylessDining))

        renamedDining.dailyBudgetOverride = false
        XCTAssertFalse(BudgetScope.includesInDailyBudget(transaction))

        transaction.dailyBudgetOverride = true
        XCTAssertTrue(BudgetScope.includesInDailyBudget(transaction))
    }

    func testDefaultDataNormalizesAllBudgetsWithoutChangingTheirFields() throws {
        let context = try makeContext()
        let primary = Ledger.defaultLedgers()[0]
        let legacy = Ledger(name: "旧账本", icon: "archivebox.fill", colorHex: "#999999")
        let category = Category(name: "自定义分类", icon: "tag.fill", colorHex: "#123456")
        let transaction = Transaction(amount: 25, category: category, ledger: legacy)
        let rule = RecurringRule(title: "旧周期", amount: 30, nextDueDate: Date(), ledger: legacy)
        let primaryTotal = Budget(monthlyLimit: 1_000, year: 2026, month: 7, ledger: primary)
        let primaryCategory = Budget(
            monthlyLimit: 200,
            year: 2026,
            month: 7,
            ledger: primary,
            categoryId: category.id
        )
        let legacyTotal = Budget(monthlyLimit: 800, year: 2026, month: 8, ledger: legacy)
        let legacyCategory = Budget(
            monthlyLimit: 150,
            year: 2026,
            month: 8,
            ledger: legacy,
            categoryId: category.id
        )
        let originalBudgets = [primaryTotal, primaryCategory, legacyTotal, legacyCategory]
        let originalFields = Dictionary(uniqueKeysWithValues: originalBudgets.map {
            ($0.id, ($0.monthlyLimit, $0.year, $0.month, $0.categoryId, $0.createdAt))
        })

        context.insert(primary)
        context.insert(legacy)
        context.insert(category)
        context.insert(transaction)
        context.insert(rule)
        originalBudgets.forEach(context.insert)
        try context.save()

        let service = DefaultDataService(modelContext: context)
        try service.stageDefaultData()
        try context.save()

        let ledgers = try context.fetch(FetchDescriptor<Ledger>())
        let budgets = try context.fetch(FetchDescriptor<Budget>())
        XCTAssertEqual(ledgers.map(\.id), [primary.id])
        XCTAssertEqual(transaction.ledger?.id, primary.id)
        XCTAssertEqual(rule.ledger?.id, primary.id)
        XCTAssertEqual(Set(budgets.map(\.id)), Set(originalBudgets.map(\.id)))
        XCTAssertTrue(budgets.allSatisfy { $0.ledger == nil })
        for budget in budgets {
            let original = try XCTUnwrap(originalFields[budget.id])
            XCTAssertEqual(budget.monthlyLimit, original.0)
            XCTAssertEqual(budget.year, original.1)
            XCTAssertEqual(budget.month, original.2)
            XCTAssertEqual(budget.categoryId, original.3)
            XCTAssertEqual(budget.createdAt, original.4)
        }

        let julyReference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 15)))
        XCTAssertEqual(
            BudgetReminderService.currentBudget(
                in: budgets,
                ledger: nil,
                referenceDate: julyReference,
                payday: 1
            )?.id,
            primaryTotal.id
        )
        XCTAssertEqual(
            CategoryBudgetService.currentBudgets(
                in: budgets,
                ledger: nil,
                referenceDate: julyReference,
                payday: 1,
                calendar: calendar
            ).map(\.id),
            [primaryCategory.id]
        )

        let augustReference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 15)))
        XCTAssertEqual(
            BudgetReminderService.currentBudget(
                in: budgets,
                ledger: nil,
                referenceDate: augustReference,
                payday: 1
            )?.id,
            legacyTotal.id
        )
        XCTAssertEqual(
            CategoryBudgetService.currentBudgets(
                in: budgets,
                ledger: nil,
                referenceDate: augustReference,
                payday: 1,
                calendar: calendar
            ).map(\.id),
            [legacyCategory.id]
        )
    }

    func testDefaultDataFreezesLegacyKeylessScopeAndIsIdempotent() throws {
        let context = try makeContext()
        let legacyIncluded = Category(name: "餐饮", icon: "fork.knife", colorHex: "#111111")
        let legacyExcluded = Category(name: "自定义支出", icon: "tag.fill", colorHex: "#222222")
        let existingOverride = Category(name: "外卖", icon: "takeoutbag.fill", colorHex: "#333333")
        existingOverride.dailyBudgetOverride = false
        context.insert(legacyIncluded)
        context.insert(legacyExcluded)
        context.insert(existingOverride)
        try context.save()

        let service = DefaultDataService(modelContext: context)
        try service.stageDefaultData()

        XCTAssertEqual(legacyIncluded.dailyBudgetOverride, true)
        XCTAssertNotNil(legacyIncluded.defaultKey)
        XCTAssertTrue(BudgetScope.includesCategory(legacyIncluded))
        XCTAssertEqual(legacyExcluded.dailyBudgetOverride, false)
        XCTAssertNil(legacyExcluded.defaultKey)
        XCTAssertFalse(BudgetScope.includesCategory(legacyExcluded))
        XCTAssertEqual(existingOverride.dailyBudgetOverride, false)
        XCTAssertNotNil(existingOverride.defaultKey)
        XCTAssertFalse(BudgetScope.includesCategory(existingOverride))

        try context.save()
        let firstCategoryCount = try context.fetchCount(FetchDescriptor<FlashCount.Category>())
        let firstLedgerIDs = Set(try context.fetch(FetchDescriptor<Ledger>()).map(\.id))
        try service.stageDefaultData()
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FlashCount.Category>()), firstCategoryCount)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<Ledger>()).map(\.id)), firstLedgerIDs)
        XCTAssertEqual(legacyIncluded.dailyBudgetOverride, true)
        XCTAssertEqual(legacyExcluded.dailyBudgetOverride, false)
        XCTAssertEqual(existingOverride.dailyBudgetOverride, false)
    }

    func testCategoryBudgetIncludesChildrenAndExcludesOtherGroups() throws {
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 12)))
        let cycle = PayCycleService.cycle(containing: reference, payday: 1, calendar: calendar)
        let dining = Category(name: "餐饮", icon: "fork.knife", colorHex: "#FF0000", sortOrder: 0)
        let coffee = Category(name: "咖啡", icon: "cup.and.saucer", colorHex: "#AA0000", sortOrder: 1)
        let shopping = Category(name: "购物", icon: "bag", colorHex: "#00AA00", sortOrder: 100)
        let budget = Budget(
            monthlyLimit: 500,
            year: calendar.component(.year, from: cycle.start),
            month: calendar.component(.month, from: cycle.start),
            categoryId: dining.id
        )
        let included = Transaction(
            amount: 100,
            date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 2))),
            category: coffee
        )
        let otherGroup = Transaction(
            amount: 300,
            date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 3))),
            category: shopping
        )
        let previousCycle = Transaction(
            amount: 400,
            date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30))),
            category: coffee
        )

        let snapshots = CategoryBudgetService.snapshots(
            budgets: [budget],
            transactions: [included, otherGroup, previousCycle],
            categories: [dining, coffee, shopping],
            ledger: nil,
            referenceDate: reference,
            payday: 1,
            calendar: calendar
        )

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].category.id, dining.id)
        XCTAssertEqual(snapshots[0].analysis.totalSpent, 100)
        XCTAssertEqual(snapshots[0].analysis.remainingBudget, 400)
    }

    func testCategoryBudgetUsesNewestDuplicateForCurrentCycle() throws {
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 15)))
        let cycle = PayCycleService.cycle(containing: reference, payday: 1, calendar: calendar)
        let category = Category(name: "餐饮", icon: "fork.knife", colorHex: "#FF0000")
        let old = Budget(
            monthlyLimit: 500,
            year: calendar.component(.year, from: cycle.start),
            month: calendar.component(.month, from: cycle.start),
            categoryId: category.id
        )
        let newest = Budget(
            monthlyLimit: 800,
            year: calendar.component(.year, from: cycle.start),
            month: calendar.component(.month, from: cycle.start),
            categoryId: category.id
        )
        newest.createdAt = old.createdAt.addingTimeInterval(1)

        let selected = CategoryBudgetService.currentBudgets(
            in: [old, newest],
            ledger: nil,
            referenceDate: reference,
            payday: 1,
            calendar: calendar
        )

        XCTAssertEqual(selected.map(\.id), [newest.id])
    }
}
