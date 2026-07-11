import XCTest
import SwiftData
@testable import FlashCount

@MainActor
final class FinanceDomainTests: XCTestCase {
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
