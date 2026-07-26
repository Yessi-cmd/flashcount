import XCTest
import SwiftData
@testable import FlashCount

// MARK: - 周期规则与 CSV 导入

extension FinanceDomainTests {
    func testRecurringSkipKeepsMonthEndAnchor() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let february = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 2, day: 28)))
        let next = try XCTUnwrap(RecurringFrequency.monthly.nextDate(from: february, anchorDay: 31, calendar: calendar))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: next), DateComponents(year: 2025, month: 3, day: 31))
    }

    func testRecurringProcessingIsIdempotentForTheSameDueDate() throws {
        let context = try makeContext()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let rule = RecurringRule(title: "测试订阅", amount: 10, nextDueDate: yesterday)
        context.insert(rule)
        try context.save()

        XCTAssertEqual(try RecurringService(modelContext: context).processAllDueRules(), 1)
        XCTAssertEqual(try RecurringService(modelContext: context).processAllDueRules(), 0)

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

        XCTAssertEqual(imported.imported, 1)
        XCTAssertEqual(imported.skipped, 1)
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions.first?.ledger?.isDefault, true)
        XCTAssertEqual(transactions.first?.cashPoolDelta, Decimal(string: "-12.34"))
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states.first?.transactionDelta, Decimal(string: "-12.34"))
    }

    func testCSVImportSupportsQuotedNewlinesAndReportsSkippedRows() throws {
        let context = try makeContext()
        let firstID = UUID()
        let csv = """
        id,date,type,amount,category,note,dailyBudget
        \"\(firstID.uuidString.lowercased())\",\"2026-07-01T08:00:00Z\",\"expense\",\"12.34\",\"餐饮\",\"第一行
        第二行，含逗号\",\"include\"
        \"not-a-uuid\",\"2026-07-01T08:00:00Z\",\"expense\",\"12.34\",\"餐饮\",\"坏行\",\"inherit\"
        """
        let url = try temporaryFile(named: "multiline-transactions.csv", contents: Data(csv.utf8))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = try CSVTransactionService(modelContext: context).importCSV(from: url)
        let transaction = try XCTUnwrap(context.fetch(FetchDescriptor<Transaction>()).first)
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(transaction.id, firstID)
        XCTAssertEqual(transaction.note, "第一行\n第二行，含逗号")
        XCTAssertEqual(transaction.dailyBudgetOverride, true)
    }
}
