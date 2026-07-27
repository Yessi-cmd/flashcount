import SwiftData
import XCTest
@testable import FlashCount

/// CSV 导入导出的边界条件。
///
/// 导入是少数「用户会喂进任意内容」的入口，每一条拒绝理由都要能落到具体行号——
/// 只说「导入失败」的话，用户面对上千行文件无从下手。
@MainActor
final class CSVTransactionServiceTests: XCTestCase {
    // MARK: - 导出

    func testExportWritesHeaderAndOneRowPerTransaction() throws {
        let context = try makeContext()
        let category = Category(name: "餐饮", icon: "fork.knife", colorHex: "#FF7A70")
        context.insert(category)
        context.insert(Transaction(amount: 12, note: "早餐", date: Date(timeIntervalSince1970: 1_700_000_000), category: category))
        context.insert(Transaction(amount: 500, isExpense: false, note: "工资", date: Date(timeIntervalSince1970: 1_700_100_000)))
        try context.save()

        let url = try CSVTransactionService(modelContext: context).exportToFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)

        XCTAssertEqual(lines.first, "id,date,type,amount,category,note,dailyBudget")
        XCTAssertEqual(lines.count, 3, "表头 + 两笔交易")
        XCTAssertTrue(lines[1].contains("expense"))
        XCTAssertTrue(lines[2].contains("income"))
    }

    /// 备注里的逗号、引号和换行必须转义，否则导出的文件自己就读不回来。
    func testExportEscapesCommasQuotesAndNewlines() throws {
        let context = try makeContext()
        context.insert(Transaction(amount: 9, note: "带,逗号 和\"引号\"\n还有换行"))
        try context.save()

        let service = CSVTransactionService(modelContext: context)
        let url = try service.exportToFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let content = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(content.contains("\"\"引号\"\""), "内嵌引号应双写转义")

        // 真正的判据：导回去还是同一条备注。
        let destination = try makeContext()
        let result = try CSVTransactionService(modelContext: destination).importCSV(from: url)
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.skippedRows, [])
        let restored = try XCTUnwrap(destination.fetch(FetchDescriptor<Transaction>()).first)
        XCTAssertEqual(restored.note, "带,逗号 和\"引号\"\n还有换行")
    }

    func testDailyBudgetOverrideSurvivesRoundTrip() throws {
        let context = try makeContext()
        let included = Transaction(amount: 10, note: "计入")
        included.dailyBudgetOverride = true
        let excluded = Transaction(amount: 20, note: "不计入")
        excluded.dailyBudgetOverride = false
        context.insert(included)
        context.insert(excluded)
        context.insert(Transaction(amount: 30, note: "跟随分类"))
        try context.save()

        let url = try CSVTransactionService(modelContext: context).exportToFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let destination = try makeContext()
        _ = try CSVTransactionService(modelContext: destination).importCSV(from: url)
        let byNote = Dictionary(
            uniqueKeysWithValues: try destination.fetch(FetchDescriptor<Transaction>()).map { ($0.note, $0) }
        )

        XCTAssertEqual(byNote["计入"]?.dailyBudgetOverride, true)
        XCTAssertEqual(byNote["不计入"]?.dailyBudgetOverride, false)
        XCTAssertNil(byNote["跟随分类"]?.dailyBudgetOverride, "inherit 应还原成「跟随分类」而不是写死一个值")
    }

    // MARK: - 表头校验

    func testHeaderMustMatchExpectedColumns() throws {
        let context = try makeContext()
        let service = CSVTransactionService(modelContext: context)

        for bad in [
            "id,date,type,amount,category\n",                      // 少一列
            "date,id,type,amount,category,note\n",                 // 顺序不对
            "id,date,type,amount,category,note,unexpected\n"       // 第七列名字不对
        ] {
            let url = try write(bad)
            defer { try? FileManager.default.removeItem(at: url) }
            XCTAssertThrowsError(try service.importCSV(from: url), "表头 \(bad) 应被拒绝") { error in
                XCTAssertEqual(error as? CSVTransactionService.ImportError, .invalidHeader)
            }
        }
    }

    /// 表格软件常在 UTF-8 文件开头写 BOM，不容忍它会让导出再导入直接失败。
    func testHeaderToleratesByteOrderMark() throws {
        let context = try makeContext()
        let url = try write("\u{FEFF}id,date,type,amount,category,note\n")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try CSVTransactionService(modelContext: context).importCSV(from: url)
        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.skippedRows, [])
    }

    func testUnterminatedQuoteIsRejected() throws {
        let context = try makeContext()
        let url = try write("id,date,type,amount,category,note\n\"未闭合\n")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try CSVTransactionService(modelContext: context).importCSV(from: url)) { error in
            XCTAssertEqual(error as? CSVTransactionService.ImportError, .malformedCSV)
        }
    }

    // MARK: - 逐行拒绝理由

    /// 一行坏数据不该拖垮整个文件，而且每条拒绝都要带上行号与原因。
    func testEachRejectionReportsItsRowNumberAndReason() throws {
        let context = try makeContext()
        let valid = UUID().uuidString
        let csv = """
        id,date,type,amount,category,note
        not-a-uuid,2026-07-01T10:00:00Z,expense,10,餐饮,坏ID
        \(UUID().uuidString),2026/07/01,expense,10,餐饮,坏日期
        \(UUID().uuidString),2026-07-01T10:00:00Z,expense,0,餐饮,零金额
        \(UUID().uuidString),2026-07-01T10:00:00Z,transfer,10,餐饮,坏类型
        \(UUID().uuidString),2026-07-01T10:00:00Z,expense
        \(valid),2026-07-01T10:00:00Z,expense,25.5,餐饮,好行

        """
        let url = try write(csv)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try CSVTransactionService(modelContext: context).importCSV(from: url)

        XCTAssertEqual(result.imported, 1, "只有最后一行是好的")
        XCTAssertEqual(result.skippedRows.map(\.rowNumber), [2, 3, 4, 5, 6])
        XCTAssertEqual(result.skippedRows.map(\.reason), [
            "ID 不是有效 UUID",
            "日期不是 ISO 8601 格式",
            "金额必须大于零",
            "type 必须为 expense 或 income",
            "列数不足"
        ])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Transaction>()).first?.amount, Decimal(string: "25.5"))
    }

    /// 分类按「名称 + 收支类型」匹配：同名的收入分类不该被支出行认领。
    func testCategoryMatchingRespectsExpenseFlag() throws {
        let context = try makeContext()
        let expenseCategory = Category(name: "奖金", icon: "gift", colorHex: "#111111", isExpense: true)
        let incomeCategory = Category(name: "奖金", icon: "gift", colorHex: "#222222", isExpense: false)
        context.insert(expenseCategory)
        context.insert(incomeCategory)
        try context.save()

        let url = try write("""
        id,date,type,amount,category,note
        \(UUID().uuidString),2026-07-01T10:00:00Z,income,800,奖金,年终

        """)
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try CSVTransactionService(modelContext: context).importCSV(from: url)
        let restored = try XCTUnwrap(context.fetch(FetchDescriptor<Transaction>()).first)
        XCTAssertEqual(restored.category?.id, incomeCategory.id, "收入行应匹配收入侧的同名分类")
    }

    /// 认不出的分类名只让这一笔无分类，不该整行丢弃——金额和日期仍是有效信息。
    func testUnknownCategoryStillImportsTransactionWithoutCategory() throws {
        let context = try makeContext()
        let url = try write("""
        id,date,type,amount,category,note
        \(UUID().uuidString),2026-07-01T10:00:00Z,expense,15,不存在的分类,备注

        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try CSVTransactionService(modelContext: context).importCSV(from: url)
        XCTAssertEqual(result.imported, 1)
        XCTAssertNil(try context.fetch(FetchDescriptor<Transaction>()).first?.category)
    }

    /// 导入必须同步资金池，否则账本里多了钱而可动用资金没变。
    func testImportAppliesNetCashDeltaToCashPool() throws {
        let context = try makeContext()
        context.insert(CashPoolState(transactionDelta: 0))
        try context.save()

        let url = try write("""
        id,date,type,amount,category,note
        \(UUID().uuidString),2026-07-01T10:00:00Z,expense,30,,支出
        \(UUID().uuidString),2026-07-02T10:00:00Z,income,100,,收入

        """)
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try CSVTransactionService(modelContext: context).importCSV(from: url)

        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CashPoolState>()).first?.transactionDelta,
            70,
            "净影响应为 -30 + 100"
        )
    }

    // MARK: - 夹具

    private func write(_ content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("csv-\(UUID().uuidString).csv")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(versionedSchema: FlashCountSchemaV3.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}
