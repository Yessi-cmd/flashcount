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

    func testReminderMutationsKeepCallerStateWhenPersistenceFails() {
        let original = [ReminderItem(title: "原提醒", dueDate: Date().addingTimeInterval(60))]
        let service = ReminderMutationService(store: FailingReminderStore())

        XCTAssertThrowsError(try service.adding(ReminderItem(title: "新提醒", dueDate: Date().addingTimeInterval(120)), to: original))
        XCTAssertThrowsError(try service.completing(id: original[0].id, in: original))
        XCTAssertThrowsError(try service.deleting(id: original[0].id, from: original))
        XCTAssertEqual(original.count, 1)
        XCTAssertFalse(original[0].isCompleted)
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

    func testDailyBudgetScopeExcludesClothingAndAllowsCategoryAndTransactionOverrides() {
        let clothing = Category(name: "服饰鞋包", icon: "tshirt.fill", colorHex: "#000000")
        let transaction = Transaction(amount: 200, category: clothing)

        XCTAssertFalse(BudgetScope.includesCategory(clothing))
        XCTAssertFalse(BudgetScope.includesInDailyBudget(transaction))

        clothing.dailyBudgetOverride = true
        XCTAssertTrue(BudgetScope.includesInDailyBudget(transaction))

        transaction.dailyBudgetOverride = false
        XCTAssertFalse(BudgetScope.includesInDailyBudget(transaction))
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
            configurations: configuration
        )
        return ModelContext(container)
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

private struct FailingReminderStore: ReminderPersisting {
    struct Failure: Error {}
    func load() -> [ReminderItem] { [] }
    func save(_ reminders: [ReminderItem]) throws { throw Failure() }
}
