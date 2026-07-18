import XCTest
import SwiftData
@testable import FlashCount

@MainActor
final class FinanceDomainTests: XCTestCase {
    func testCodableMoneyRejectsInvalidStrings() {
        XCTAssertThrowsError(try JSONDecoder().decode(CodableMoney.self, from: Data("\"not-money\"".utf8)))
    }

    func testMoneyValidationAndModelsClampInvalidProgress() {
        XCTAssertFalse(MoneyValidation.nonNegative(-1))
        XCTAssertFalse(MoneyValidation.validPhysicalAsset(purchasePrice: 100, salvageValue: 101, targetDailyCost: 1))

        let goal = SavingsGoal(name: "应急金", targetAmount: 100, currentAmount: -20)
        XCTAssertEqual(goal.currentAmount, 0)
        XCTAssertEqual(goal.progress, 0)

        let liability = Asset(name: "信用卡", type: .creditCard, balance: -100)
        XCTAssertEqual(liability.balance, 0)
        XCTAssertEqual(liability.signedBalance, 0)
    }

    func testRecurringSkipKeepsMonthEndAnchor() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let february = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 2, day: 28)))
        let next = try XCTUnwrap(RecurringFrequency.monthly.nextDate(from: february, anchorDay: 31, calendar: calendar))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: next), DateComponents(year: 2025, month: 3, day: 31))
    }

    func testReminderStoreFailureDoesNotReplaceExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileReminderStore(fileURL: directory)
        XCTAssertThrowsError(try store.save([ReminderItem(title: "test", dueDate: Date().addingTimeInterval(60))]))
    }

    func testLegacyReminderMigrationImportsOnceAndRetainsOriginalJSON() throws {
        let context = try makeContext()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("flashcount-reminders.json")
        let legacyStore = FileReminderStore(fileURL: fileURL)
        let dueDate = Date(timeIntervalSince1970: 1_784_000_000)
        let pending = ReminderItem(title: "旧提醒", note: "保留", dueDate: dueDate, intensity: .strong)
        let completed = ReminderItem(
            title: "已完成提醒",
            dueDate: dueDate.addingTimeInterval(60),
            isCompleted: true,
            completedAt: dueDate.addingTimeInterval(30)
        )
        try legacyStore.save([pending, completed])

        let suiteName = "ReminderMigrationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = ReminderDataService(
            modelContext: context,
            legacyStore: legacyStore,
            userDefaults: defaults,
            migrationKey: "test-reminder-migration"
        )

        XCTAssertEqual(try service.migrateLegacyFileIfNeeded(), 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let migrated = try service.load().sorted { $0.id.uuidString < $1.id.uuidString }
        let expected = [pending, completed].sorted { $0.id.uuidString < $1.id.uuidString }
        XCTAssertEqual(migrated.count, expected.count)
        for (actual, expected) in zip(migrated, expected) {
            assertReminder(actual, matches: expected)
        }
        XCTAssertEqual(try service.migrateLegacyFileIfNeeded(), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Reminder>()), 2)
    }

    func testReminderDatabaseMutationsPreserveCompletionAndIdentity() throws {
        let context = try makeContext()
        let service = ReminderDataService(modelContext: context)
        let reminder = ReminderItem(title: "数据库提醒", dueDate: Date().addingTimeInterval(60))

        XCTAssertEqual(try service.add(reminder), [reminder])
        let completedAt = Date()
        let completed = try service.complete(id: reminder.id, at: completedAt)
        XCTAssertEqual(completed.first?.id, reminder.id)
        XCTAssertTrue(completed.first?.isCompleted == true)
        XCTAssertEqual(completed.first?.completedAt, completedAt)

        XCTAssertTrue(try service.delete(id: reminder.id).isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Reminder>()), 0)
    }

    func testAuthoritativeRestoreSkipsRetainedLegacyReminderFile() throws {
        let context = try makeContext()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("flashcount-reminders.json")
        let legacyStore = FileReminderStore(fileURL: fileURL)
        try legacyStore.save([ReminderItem(title: "过期旧提醒", dueDate: Date().addingTimeInterval(60))])

        let suiteName = "ReminderRestoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = ReminderDataService(
            modelContext: context,
            legacyStore: legacyStore,
            userDefaults: defaults,
            migrationKey: "test-reminder-replace"
        )

        service.markLegacyFileMigrationComplete()
        XCTAssertEqual(try service.migrateLegacyFileIfNeeded(), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Reminder>()), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testAddingReminderModelPreservesExistingSwiftDataStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("FlashCount.store")

        let original = Transaction(amount: Decimal(string: "42.50")!, note: "升级前交易")
        let originalID = original.id
        let originalAmount = original.amount
        let originalNote = original.note
        do {
            let legacyConfiguration = ModelConfiguration(
                "FlashCount",
                schema: Schema(legacyModelTypes),
                url: storeURL,
                cloudKitDatabase: .none
            )
            let legacyContainer = try ModelContainer(
                for: Transaction.self,
                Category.self,
                Ledger.self,
                RecurringRule.self,
                Budget.self,
                Asset.self,
                PhysicalAsset.self,
                CashPoolItem.self,
                CashPoolState.self,
                SavingsGoal.self,
                InstallmentBill.self,
                TransactionTemplate.self,
                configurations: legacyConfiguration
            )
            let legacyContext = ModelContext(legacyContainer)
            legacyContext.insert(original)
            try legacyContext.save()
        }

        let upgradedConfiguration = ModelConfiguration(
            "FlashCount",
            schema: Schema(legacyModelTypes + [Reminder.self]),
            url: storeURL,
            cloudKitDatabase: .none
        )
        let upgradedContainer = try ModelContainer(
            for: Transaction.self,
            Category.self,
            Ledger.self,
            RecurringRule.self,
            Budget.self,
            Asset.self,
            PhysicalAsset.self,
            CashPoolItem.self,
            CashPoolState.self,
            SavingsGoal.self,
            InstallmentBill.self,
            TransactionTemplate.self,
            Reminder.self,
            configurations: upgradedConfiguration
        )
        let upgradedContext = ModelContext(upgradedContainer)

        let restored = try XCTUnwrap(upgradedContext.fetch(FetchDescriptor<Transaction>()).first)
        XCTAssertEqual(restored.id, originalID)
        XCTAssertEqual(restored.amount, originalAmount)
        XCTAssertEqual(restored.note, originalNote)

        let reminder = ReminderItem(title: "升级后提醒", dueDate: Date().addingTimeInterval(60))
        _ = try ReminderDataService(modelContext: upgradedContext).add(reminder)
        XCTAssertEqual(try upgradedContext.fetchCount(FetchDescriptor<Reminder>()), 1)
    }

    func testDuplicateBackupUUIDIsRejectedBeforeReplaceMutatesData() throws {
        let context = try makeContext()
        context.insert(Transaction(amount: 10))
        context.insert(Transaction(amount: 20))
        try context.save()
        let service = DataBackupService(modelContext: context)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: service.exportJSON()) as? [String: Any])
        var transactions = try XCTUnwrap(json["transactions"] as? [[String: Any]])
        transactions[1]["id"] = transactions[0]["id"]
        json["transactions"] = transactions
        let invalidBackup = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try service.importJSON(data: invalidBackup, mode: .replace))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 2)
    }
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

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

    func testLedgerPeriodFiltersDistinguishTodayMonthAndPayCycle() throws {
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 12)))
        let customStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 2)))
        let customEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 4)))

        let today = try XCTUnwrap(LedgerPeriodFilter.today.dateRange(
            referenceDate: date, payday: 25, customStart: customStart, customEnd: customEnd, calendar: calendar
        ))
        let month = try XCTUnwrap(LedgerPeriodFilter.thisMonth.dateRange(
            referenceDate: date, payday: 25, customStart: customStart, customEnd: customEnd, calendar: calendar
        ))
        let cycle = try XCTUnwrap(LedgerPeriodFilter.payCycle.dateRange(
            referenceDate: date, payday: 25, customStart: customStart, customEnd: customEnd, calendar: calendar
        ))

        XCTAssertEqual(calendar.component(.day, from: today.lowerBound), 11)
        XCTAssertEqual(calendar.component(.day, from: today.upperBound), 12)
        XCTAssertEqual(calendar.component(.day, from: month.lowerBound), 1)
        XCTAssertEqual(calendar.component(.month, from: month.upperBound), 8)
        XCTAssertEqual(calendar.component(.day, from: cycle.lowerBound), 25)
        XCTAssertEqual(calendar.component(.month, from: cycle.lowerBound), 6)
        XCTAssertEqual(LedgerPeriodFilter.payCycle.metricPrefix, "本周期")
        XCTAssertEqual(LedgerPeriodFilter.thisMonth.metricPrefix, "本月")
    }

    func testPrivacyPolicyUsesOneUnlockStateForIncomeAndAssets() {
        XCTAssertFalse(PrivacyVisibilityPolicy.hidesIncome(isExpense: true, isUnlocked: false))
        XCTAssertTrue(PrivacyVisibilityPolicy.hidesIncome(isExpense: false, isUnlocked: false))
        XCTAssertFalse(PrivacyVisibilityPolicy.hidesIncome(isExpense: false, isUnlocked: true))

        XCTAssertTrue(PrivacyVisibilityPolicy.hidesAssets(isUnlocked: false))
        XCTAssertFalse(PrivacyVisibilityPolicy.hidesAssets(isUnlocked: true))
    }

    func testPrivacyPolicyOnlyHidesProtectedIncomeMetadataWhileLocked() {
        XCTAssertFalse(PrivacyVisibilityPolicy.hidesProtectedMetadata(isProtectedIncome: false, isUnlocked: false))
        XCTAssertTrue(PrivacyVisibilityPolicy.hidesProtectedMetadata(isProtectedIncome: true, isUnlocked: false))
        XCTAssertFalse(PrivacyVisibilityPolicy.hidesProtectedMetadata(isProtectedIncome: true, isUnlocked: true))
    }

    func testPrivacyRevealRequiresConfirmationBeforeAuthentication() {
        let privacyLock = PrivacyLockService()

        XCTAssertFalse(privacyLock.isUnlocked)
        XCTAssertFalse(privacyLock.isRevealConfirmationPresented)

        privacyLock.requestReveal()

        XCTAssertFalse(privacyLock.isUnlocked)
        XCTAssertTrue(privacyLock.isRevealConfirmationPresented)

        privacyLock.lock()
        XCTAssertFalse(privacyLock.isRevealConfirmationPresented)
        XCTAssertFalse(privacyLock.isUnlocked)
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

    func testBackupRestoresDailyBudgetOverrides() throws {
        let context = try makeContext()
        let category = Category(name: "服饰鞋包", icon: "tshirt.fill", colorHex: "#000000")
        category.dailyBudgetOverride = true
        let ledger = Ledger.defaultLedgers()[0]
        let transaction = Transaction(
            amount: 200,
            dailyBudgetOverride: false,
            category: category,
            ledger: ledger
        )
        context.insert(category)
        context.insert(ledger)
        context.insert(transaction)
        try context.save()

        let service = DataBackupService(modelContext: context)
        let snapshot = try service.exportJSON()
        _ = try service.importJSON(data: snapshot, mode: .replace)

        let restoredCategory = try XCTUnwrap(context.fetch(FetchDescriptor<FlashCount.Category>()).first { $0.name == "服饰鞋包" })
        let restoredTransaction = try XCTUnwrap(context.fetch(FetchDescriptor<Transaction>()).first)
        XCTAssertEqual(restoredCategory.dailyBudgetOverride, true)
        XCTAssertEqual(restoredTransaction.dailyBudgetOverride, false)
    }

    func testBackupRestoresCategoryHierarchyAndMergeMetadata() throws {
        let context = try makeContext()
        let root = Category(name: "自定义生活", icon: "house.fill", colorHex: "#123456", isExpense: true)
        let child = Category(
            name: "自定义咖啡",
            icon: "cup.and.saucer.fill",
            colorHex: "#654321",
            isExpense: true,
            parentCategoryName: root.name,
            defaultKey: "custom.test.child"
        )
        let merged = Category(name: "旧咖啡", icon: "cup.and.saucer", colorHex: "#999999", isExpense: true)
        merged.isArchived = true
        merged.mergedIntoCategoryID = child.id
        context.insert(root)
        context.insert(child)
        context.insert(merged)
        try context.save()

        let service = DataBackupService(modelContext: context)
        let snapshot = try service.exportJSON()
        _ = try service.importJSON(data: snapshot, mode: .replace)

        let restored = try context.fetch(FetchDescriptor<FlashCount.Category>())
        let restoredChild = try XCTUnwrap(restored.first { $0.name == child.name })
        let restoredMerged = try XCTUnwrap(restored.first { $0.name == merged.name })
        XCTAssertEqual(restoredChild.parentCategoryName, root.name)
        XCTAssertEqual(restoredChild.defaultKey, "custom.test.child")
        XCTAssertEqual(restoredMerged.mergedIntoCategoryID, restoredChild.id)
    }

    func testRecurringProcessingIsIdempotentForTheSameDueDate() throws {
        let context = try makeContext()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let rule = RecurringRule(title: "测试订阅", amount: 10, nextDueDate: yesterday)
        context.insert(rule)
        try context.save()

        XCTAssertEqual(RecurringService(modelContext: context).processAllDueRules(), 1)
        XCTAssertEqual(RecurringService(modelContext: context).processAllDueRules(), 0)

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions.first?.date, yesterday)
    }

    func testMonthlyRecurringRestoresAnchorAfterShortMonth() throws {
        let january31 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 9)))
        let february = try XCTUnwrap(
            RecurringFrequency.monthly.nextDate(from: january31, anchorDay: 31, calendar: calendar)
        )
        let march = try XCTUnwrap(
            RecurringFrequency.monthly.nextDate(from: february, anchorDay: 31, calendar: calendar)
        )

        XCTAssertEqual(calendar.component(.day, from: february), 28)
        XCTAssertEqual(calendar.component(.month, from: february), 2)
        XCTAssertEqual(calendar.component(.day, from: march), 31)
        XCTAssertEqual(calendar.component(.month, from: march), 3)
    }

    func testCSVImportAssignsLedgerUpdatesCashPoolAndDeduplicatesFileRows() throws {
        let context = try makeContext()
        let id = UUID()
        let csv = """
        id,date,type,amount,category,note
        "\(id.uuidString)","2026-07-01T08:00:00Z","expense","12.34","餐饮","午餐"
        "\(id.uuidString)","2026-07-01T08:00:00Z","expense","12.34","餐饮","重复行"
        """
        let url = try temporaryFile(named: "transactions.csv", contents: Data(csv.utf8))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let imported = try CSVTransactionService(modelContext: context).importCSV(from: url)
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let states = try context.fetch(FetchDescriptor<CashPoolState>())

        XCTAssertEqual(imported, 1)
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions.first?.ledger?.isDefault, true)
        XCTAssertEqual(transactions.first?.cashPoolDelta, Decimal(string: "-12.34"))
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states.first?.transactionDelta, Decimal(string: "-12.34"))
    }

    func testFutureBackupVersionIsRejectedBeforeReplaceMutatesData() throws {
        let context = try makeContext()
        let original = Transaction(amount: 42, note: "保留我")
        context.insert(original)
        try context.save()

        let service = DataBackupService(modelContext: context)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: service.exportJSON()) as? [String: Any])
        json["version"] = "99.0.0"
        let futureBackup = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try service.importJSON(data: futureBackup, mode: .replace)) { error in
            guard case DataBackupService.ImportError.unsupportedVersion("99.0.0") = error else {
                return XCTFail("预期版本不兼容错误，实际为 \(error)")
            }
        }

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(transactions.map(\.id), [original.id])
    }

    func testReplaceBackupRestoresSnapshotAndRecurringAnchor() throws {
        let context = try makeContext()
        let ledger = Ledger.defaultLedgers()[0]
        let source = Transaction(
            amount: 10,
            note: "备份内",
            cashPoolDelta: -10,
            ledger: ledger
        )
        let dueDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 9)))
        let rule = RecurringRule(
            title: "月底账单",
            amount: 10,
            frequency: .monthly,
            nextDueDate: dueDate,
            ledger: ledger
        )
        context.insert(ledger)
        context.insert(source)
        context.insert(rule)
        context.insert(CashPoolState(transactionDelta: -10))
        try context.save()

        let service = DataBackupService(modelContext: context)
        let snapshot = try service.exportJSON()
        context.insert(Transaction(amount: 99, note: "备份外", ledger: ledger))
        try context.save()

        _ = try service.importJSON(data: snapshot, mode: .replace)

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let rules = try context.fetch(FetchDescriptor<RecurringRule>())
        let states = try context.fetch(FetchDescriptor<CashPoolState>())
        XCTAssertEqual(transactions.map(\.note), ["备份内"])
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.anchorDay, 31)
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states.first?.transactionDelta, -10)
    }

    func testBackupRoundTripRestoresSwiftDataReminders() throws {
        let context = try makeContext()
        let service = ReminderDataService(modelContext: context)
        let original = ReminderItem(title: "备份中的提醒", note: "保留", dueDate: Date().addingTimeInterval(3_600))
        _ = try service.add(original)

        let backupService = DataBackupService(modelContext: context)
        let snapshot = try backupService.exportJSON()
        _ = try service.add(ReminderItem(title: "备份外提醒", dueDate: Date().addingTimeInterval(7_200)))

        _ = try backupService.importJSON(data: snapshot, mode: .replace)

        let restored = try XCTUnwrap(ReminderDataService(modelContext: context).load().first)
        assertReminder(restored, matches: original)
    }

    func testPreviousBackupWithoutAnchorFieldsRemainsImportable() throws {
        let context = try makeContext()
        let dueDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 9)))
        context.insert(RecurringRule(title: "旧版月底账单", amount: 20, frequency: .monthly, nextDueDate: dueDate))
        try context.save()

        let service = DataBackupService(modelContext: context)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: service.exportJSON()) as? [String: Any])
        json["version"] = "1.5.0"
        var rules = try XCTUnwrap(json["recurringRules"] as? [[String: Any]])
        rules[0].removeValue(forKey: "anchorDay")
        rules[0].removeValue(forKey: "endDate")
        json["recurringRules"] = rules
        let previousBackup = try JSONSerialization.data(withJSONObject: json)

        _ = try service.importJSON(data: previousBackup, mode: .replace)

        let importedRules = try context.fetch(FetchDescriptor<RecurringRule>())
        XCTAssertEqual(importedRules.count, 1)
        XCTAssertEqual(importedRules.first?.anchorDay, 31)
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Transaction.self,
            Category.self,
            Ledger.self,
            RecurringRule.self,
            Budget.self,
            Asset.self,
            PhysicalAsset.self,
            CashPoolItem.self,
            CashPoolState.self,
            SavingsGoal.self,
            InstallmentBill.self,
            TransactionTemplate.self,
            Reminder.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    private var legacyModelTypes: [any PersistentModel.Type] {
        [
            Transaction.self,
            Category.self,
            Ledger.self,
            RecurringRule.self,
            Budget.self,
            Asset.self,
            PhysicalAsset.self,
            CashPoolItem.self,
            CashPoolState.self,
            SavingsGoal.self,
            InstallmentBill.self,
            TransactionTemplate.self
        ]
    }

    private func assertReminder(
        _ actual: ReminderItem,
        matches expected: ReminderItem,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.id, expected.id, file: file, line: line)
        XCTAssertEqual(actual.title, expected.title, file: file, line: line)
        XCTAssertEqual(actual.note, expected.note, file: file, line: line)
        XCTAssertEqual(actual.intensity, expected.intensity, file: file, line: line)
        XCTAssertEqual(actual.isCompleted, expected.isCompleted, file: file, line: line)
        XCTAssertEqual(actual.dueDate.timeIntervalSince1970, expected.dueDate.timeIntervalSince1970, accuracy: 1, file: file, line: line)
        XCTAssertEqual(actual.createdAt.timeIntervalSince1970, expected.createdAt.timeIntervalSince1970, accuracy: 1, file: file, line: line)
        switch (actual.completedAt, expected.completedAt) {
        case (nil, nil):
            break
        case let (.some(actualDate), .some(expectedDate)):
            XCTAssertEqual(
                actualDate.timeIntervalSince1970,
                expectedDate.timeIntervalSince1970,
                accuracy: 1,
                file: file,
                line: line
            )
        default:
            XCTFail("completedAt 不一致", file: file, line: line)
        }
    }

    private func temporaryFile(named name: String, contents: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlashCountTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, options: .atomic)
        return url
    }
}
