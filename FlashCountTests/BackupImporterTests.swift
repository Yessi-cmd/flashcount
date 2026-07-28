import SwiftData
import XCTest
@testable import FlashCount

/// 备份导入里此前完全没有测试覆盖的几条路：预览、合并去重、实物资产、
/// 以及枚举取值非法时的跳过。
///
/// 这些都不是边角行为——「同一份备份导入两次」是最容易发生的用户操作，
/// 而预览若有副作用会在用户还没确认时就改数据。
@MainActor
final class BackupImporterTests: XCTestCase {
    // MARK: - 预览

    /// 预览必须只读。用户看到摘要之后还可以取消，这时数据不该已经变了。
    func testPreviewReportsCountsWithoutTouchingData() throws {
        let source = try makeContext()
        source.insert(Category(name: "预览分类", icon: "tag.fill", colorHex: "#112233"))
        source.insert(Transaction(amount: 12))
        source.insert(Reminder(item: ReminderItem(title: "预览提醒", dueDate: Date())))
        try source.save()
        let snapshot = try DataBackupService(modelContext: source).exportJSON()

        let destination = try makeContext()
        let service = DataBackupService(modelContext: destination)
        let preview = try service.previewJSON(data: snapshot)

        XCTAssertEqual(preview.version, DataBackupService.currentBackupVersion)
        XCTAssertGreaterThan(preview.itemCount, 0)
        XCTAssertEqual(preview.reminderCount, 1)
        XCTAssertTrue(preview.summary.contains(preview.version))

        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<Transaction>()), 0, "预览不得写入任何数据")
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<FlashCount.Category>()), 0)
    }

    /// 版本校验要发生在预览阶段，而不是等到用户点了导入才报错。
    func testPreviewRejectsFutureVersionBeforeUserCommits() throws {
        let context = try makeContext()
        let service = DataBackupService(modelContext: context)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try service.exportJSON()) as? [String: Any])
        json["version"] = "999.0.0"

        XCTAssertThrowsError(
            try service.previewJSON(data: try JSONSerialization.data(withJSONObject: json))
        )
    }

    /// 文件入口和 Data 入口必须给出同一个结果——UI 走的是文件那条。
    func testPreviewFromFileMatchesPreviewFromData() throws {
        let source = try makeContext()
        source.insert(Transaction(amount: 7))
        try source.save()
        let snapshot = try DataBackupService(modelContext: source).exportJSON()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-\(UUID().uuidString).json")
        try snapshot.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let service = DataBackupService(modelContext: try makeContext())
        let fromData = try service.previewJSON(data: snapshot)
        let fromFile = try service.previewJSON(from: url)

        XCTAssertEqual(fromFile.itemCount, fromData.itemCount)
        XCTAssertEqual(fromFile.version, fromData.version)
    }

    func testReplaceImportRejectsMalformedRelationshipUUIDWithoutCrashing() throws {
        let source = try makeContext()
        let category = Category(name: "关系分类", icon: "tag.fill", colorHex: "#112233")
        source.insert(category)
        source.insert(Transaction(amount: 7, category: category))
        try source.save()

        let service = DataBackupService(modelContext: source)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try service.exportJSON()) as? [String: Any])
        var transactions = try XCTUnwrap(json["transactions"] as? [[String: Any]])
        transactions[0]["categoryId"] = "not-a-uuid"
        json["transactions"] = transactions

        let destination = try makeContext()
        XCTAssertThrowsError(
            try DataBackupService(modelContext: destination).importJSON(
                data: try JSONSerialization.data(withJSONObject: json),
                mode: .replace
            )
        )
    }

    func testImportFromFileRestoresTheSameDataAsImportFromMemory() throws {
        let source = try makeContext()
        source.insert(Transaction(amount: 33, note: "文件导入"))
        try source.save()
        let snapshot = try DataBackupService(modelContext: source).exportJSON()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-\(UUID().uuidString).json")
        try snapshot.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let destination = try makeContext()
        _ = try DataBackupService(modelContext: destination).importJSON(from: url, mode: .merge)

        let restored = try XCTUnwrap(destination.fetch(FetchDescriptor<Transaction>()).first)
        XCTAssertEqual(restored.note, "文件导入")
        XCTAssertEqual(restored.amount, 33)
    }

    // MARK: - 合并去重

    /// 同一份备份导入两次是最容易发生的用户操作，第二次必须整份跳过。
    func testImportingTheSameBackupTwiceSkipsEverythingTheSecondTime() throws {
        let source = try makeContext()
        let ledger = Ledger.defaultLedgers()[0]
        let category = Category(name: "去重分类", icon: "tag.fill", colorHex: "#334455")
        source.insert(ledger)
        source.insert(category)
        source.insert(Transaction(amount: 18, category: category, ledger: ledger))
        try source.save()
        let snapshot = try DataBackupService(modelContext: source).exportJSON()

        let destination = try makeContext()
        let service = DataBackupService(modelContext: destination)
        let first = try service.importJSON(data: snapshot, mode: .merge)
        XCTAssertEqual(first.transactionsImported, 1)

        let transactionsAfterFirst = try destination.fetchCount(FetchDescriptor<Transaction>())
        let categoriesAfterFirst = try destination.fetchCount(FetchDescriptor<FlashCount.Category>())

        let second = try service.importJSON(data: snapshot, mode: .merge)

        XCTAssertEqual(second.transactionsImported, 0, "按 UUID 命中已有记录应跳过")
        XCTAssertGreaterThan(second.skipped, 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<Transaction>()), transactionsAfterFirst)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<FlashCount.Category>()), categoriesAfterFirst)
    }

    /// 导入不会把本产品变成多账本。
    ///
    /// `importJSON` 末尾和默认数据播种共用一次事务调用 `stageDefaultData()`，
    /// 后者做单账本整理：所有交易归到主账本，其余账本删除。所以「备份里的账本
    /// 叫什么」不影响最终结构——可观测的契约是账本恰好一个、交易挂在它上面。
    func testImportKeepsExactlyOneLedgerAndAttachesEverythingToIt() throws {
        let source = try makeContext()
        let sourceLedger = Ledger(name: "旧机器上的账本", icon: "book.fill", colorHex: "#111111")
        source.insert(sourceLedger)
        source.insert(Transaction(amount: 9, ledger: sourceLedger))
        try source.save()
        let snapshot = try DataBackupService(modelContext: source).exportJSON()

        let destination = try makeContext()
        destination.insert(Ledger(name: "本机账本", icon: "book.closed", colorHex: "#222222"))
        try destination.save()

        _ = try DataBackupService(modelContext: destination).importJSON(data: snapshot, mode: .merge)

        let ledgers = try destination.fetch(FetchDescriptor<Ledger>())
        XCTAssertEqual(ledgers.count, 1, "导入后必须仍是单账本")
        let primary = try XCTUnwrap(ledgers.first)

        let restored = try XCTUnwrap(destination.fetch(FetchDescriptor<Transaction>()).first)
        XCTAssertEqual(restored.ledger?.id, primary.id, "交易必须挂在留下来的那个账本上")
        XCTAssertEqual(restored.amount, 9, "整理账本不该动金额")
    }

    // MARK: - 实物资产

    func testPhysicalAssetsRoundTripThroughBackup() throws {
        let source = try makeContext()
        let purchaseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let asset = PhysicalAsset(
            name: "笔记本",
            category: .laptop,
            purchasePrice: 12_000,
            purchaseDate: purchaseDate,
            salvageValue: 2_000,
            targetDailyCost: 8,
            note: "主力机"
        )
        asset.soldPrice = 5_000
        asset.soldDate = purchaseDate.addingTimeInterval(86_400)
        source.insert(asset)
        try source.save()
        let snapshot = try DataBackupService(modelContext: source).exportJSON()

        let destination = try makeContext()
        let result = try DataBackupService(modelContext: destination).importJSON(data: snapshot, mode: .merge)

        XCTAssertEqual(result.physicalAssetsImported, 1)
        let restored = try XCTUnwrap(destination.fetch(FetchDescriptor<PhysicalAsset>()).first)
        XCTAssertEqual(restored.id, asset.id)
        XCTAssertEqual(restored.name, "笔记本")
        XCTAssertEqual(restored.category, .laptop)
        XCTAssertEqual(restored.purchasePrice, 12_000)
        XCTAssertEqual(restored.salvageValue, 2_000)
        XCTAssertEqual(restored.soldPrice, 5_000)
        XCTAssertEqual(restored.soldDate, asset.soldDate)
        XCTAssertEqual(restored.note, "主力机")
    }

    /// 未知的资产类别只跳过这一条，不能让整份备份导不进来。
    func testUnknownPhysicalAssetCategoryIsSkippedWithoutFailingTheImport() throws {
        let source = try makeContext()
        source.insert(PhysicalAsset(name: "未知类别", category: .phone, purchasePrice: 100))
        source.insert(Transaction(amount: 5, note: "同批次交易"))
        try source.save()

        let service = DataBackupService(modelContext: source)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try service.exportJSON()) as? [String: Any])
        var assets = try XCTUnwrap(json["physicalAssets"] as? [[String: Any]])
        assets[0]["category"] = "未来版本才有的类别"
        json["physicalAssets"] = assets

        let destination = try makeContext()
        let result = try DataBackupService(modelContext: destination).importJSON(
            data: try JSONSerialization.data(withJSONObject: json),
            mode: .merge
        )

        XCTAssertEqual(result.physicalAssetsImported, 0)
        XCTAssertGreaterThan(result.skipped, 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<PhysicalAsset>()), 0)
        XCTAssertEqual(
            try destination.fetchCount(FetchDescriptor<Transaction>()),
            1,
            "一条资产读不出来不该拖垮整份备份"
        )
    }

    /// 未知的周期频率同样只跳过那一条规则。
    func testUnknownRecurringFrequencyIsSkippedWithoutFailingTheImport() throws {
        let source = try makeContext()
        source.insert(
            RecurringRule(title: "房租", amount: 3_000, frequency: .monthly, nextDueDate: Date())
        )
        source.insert(Transaction(amount: 5))
        try source.save()

        let service = DataBackupService(modelContext: source)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try service.exportJSON()) as? [String: Any])
        var rules = try XCTUnwrap(json["recurringRules"] as? [[String: Any]])
        rules[0]["frequency"] = "每闰年"
        json["recurringRules"] = rules

        let destination = try makeContext()
        let result = try DataBackupService(modelContext: destination).importJSON(
            data: try JSONSerialization.data(withJSONObject: json),
            mode: .merge
        )

        XCTAssertEqual(result.recurringRulesImported, 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<RecurringRule>()), 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<Transaction>()), 1)
    }

    func testCashPoolBackupUsesStableKindKeyAndReadsLegacyLabel() throws {
        let source = try makeContext()
        source.insert(CashPoolItem(name: "银行卡", kind: .cash, amount: 1_000))
        try source.save()

        let service = DataBackupService(modelContext: source)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try service.exportJSON()) as? [String: Any])
        var items = try XCTUnwrap(json["cashPoolItems"] as? [[String: Any]])
        XCTAssertEqual(items[0]["kind"] as? String, "cash")

        // A backup from the previous format must remain readable too.
        items[0]["kind"] = "现金/银行卡"
        json["cashPoolItems"] = items

        let destination = try makeContext()
        let result = try DataBackupService(modelContext: destination).importJSON(
            data: try JSONSerialization.data(withJSONObject: json),
            mode: .merge
        )

        XCTAssertEqual(result.cashPoolItemsImported, 1)
        XCTAssertEqual(try destination.fetch(FetchDescriptor<CashPoolItem>()).first?.kind, .cash)
    }

    // MARK: - 资产类模型与模板

    /// 分期账单、储蓄目标、记账模板三组数据的往返。它们互不引用，但都带
    /// `isArchived`/时间戳这类容易在 DTO 映射里漏掉的字段。
    func testInstallmentSavingsAndTemplatesRoundTrip() throws {
        let source = try makeContext()
        let firstRepayment = Date(timeIntervalSince1970: 1_700_000_000)

        let bill = InstallmentBill(
            name: "手机分期",
            totalAmount: 6_000,
            installmentCount: 12,
            paidInstallments: 3,
            repaymentDay: 8,
            firstRepaymentDate: firstRepayment,
            note: "免息"
        )
        let goal = SavingsGoal(
            name: "旅行基金",
            targetAmount: 20_000,
            currentAmount: 7_500,
            targetDate: firstRepayment.addingTimeInterval(86_400 * 200),
            note: "夏天出发"
        )
        let archivedGoal = SavingsGoal(name: "已完成目标", targetAmount: 100, currentAmount: 100)
        archivedGoal.isCompleted = true
        archivedGoal.isArchived = true
        let template = TransactionTemplate(
            name: "咖啡",
            amount: Decimal(string: "9.90") ?? 9.9,
            isExpense: true,
            note: "楼下",
            categoryName: "餐饮",
            sortOrder: 2
        )
        source.insert(bill)
        source.insert(goal)
        source.insert(archivedGoal)
        source.insert(template)
        try source.save()
        let snapshot = try DataBackupService(modelContext: source).exportJSON()

        let destination = try makeContext()
        let result = try DataBackupService(modelContext: destination).importJSON(data: snapshot, mode: .merge)

        XCTAssertEqual(result.installmentBillsImported, 1)
        XCTAssertEqual(result.savingsGoalsImported, 2)
        XCTAssertEqual(result.templatesImported, 1)

        let restoredBill = try XCTUnwrap(destination.fetch(FetchDescriptor<InstallmentBill>()).first)
        XCTAssertEqual(restoredBill.id, bill.id)
        XCTAssertEqual(restoredBill.totalAmount, 6_000)
        XCTAssertEqual(restoredBill.installmentCount, 12)
        XCTAssertEqual(restoredBill.paidInstallments, 3, "已还期数必须保留，否则还款进度会倒退")
        XCTAssertEqual(restoredBill.repaymentDay, 8)
        XCTAssertEqual(restoredBill.firstRepaymentDate, firstRepayment)

        let goals = Dictionary(
            uniqueKeysWithValues: try destination.fetch(FetchDescriptor<SavingsGoal>()).map { ($0.name, $0) }
        )
        XCTAssertEqual(goals["旅行基金"]?.currentAmount, 7_500)
        XCTAssertEqual(goals["旅行基金"]?.targetDate, goal.targetDate)
        XCTAssertEqual(goals["已完成目标"]?.isCompleted, true)
        XCTAssertEqual(goals["已完成目标"]?.isArchived, true, "归档与完成状态都要跟着回来")

        let restoredTemplate = try XCTUnwrap(destination.fetch(FetchDescriptor<TransactionTemplate>()).first)
        XCTAssertEqual(restoredTemplate.amount, Decimal(string: "9.90"))
        XCTAssertEqual(restoredTemplate.categoryName, "餐饮")
        XCTAssertEqual(restoredTemplate.sortOrder, 2)
    }

    /// 这三组同样要按 UUID 去重，重复导入不能翻倍。
    func testInstallmentSavingsAndTemplatesAreDeduplicatedOnSecondImport() throws {
        let source = try makeContext()
        source.insert(InstallmentBill(
            name: "分期",
            totalAmount: 1_200,
            installmentCount: 6,
            repaymentDay: 1,
            firstRepaymentDate: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        source.insert(SavingsGoal(name: "目标", targetAmount: 500, currentAmount: 100))
        source.insert(TransactionTemplate(name: "模板", amount: 5, isExpense: true))
        try source.save()
        let snapshot = try DataBackupService(modelContext: source).exportJSON()

        let destination = try makeContext()
        let service = DataBackupService(modelContext: destination)
        _ = try service.importJSON(data: snapshot, mode: .merge)
        let second = try service.importJSON(data: snapshot, mode: .merge)

        XCTAssertEqual(second.installmentBillsImported, 0)
        XCTAssertEqual(second.savingsGoalsImported, 0)
        XCTAssertEqual(second.templatesImported, 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<InstallmentBill>()), 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<SavingsGoal>()), 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<TransactionTemplate>()), 1)
    }

    /// replace 模式必须先清空本地数据，导入结果只反映备份内容。
    func testReplaceModeDiscardsLocalDataInsteadOfMerging() throws {
        let source = try makeContext()
        source.insert(Transaction(amount: 10, note: "备份里的"))
        source.insert(SavingsGoal(name: "备份目标", targetAmount: 100, currentAmount: 10))
        try source.save()
        let snapshot = try DataBackupService(modelContext: source).exportJSON()

        let destination = try makeContext()
        destination.insert(Transaction(amount: 999, note: "本机原有"))
        destination.insert(SavingsGoal(name: "本机目标", targetAmount: 1, currentAmount: 1))
        try destination.save()

        _ = try DataBackupService(modelContext: destination).importJSON(data: snapshot, mode: .replace)

        XCTAssertEqual(try destination.fetch(FetchDescriptor<Transaction>()).map(\.note), ["备份里的"])
        XCTAssertEqual(try destination.fetch(FetchDescriptor<SavingsGoal>()).map(\.name), ["备份目标"])
    }

    // MARK: - 夹具

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(versionedSchema: FlashCountSchemaV3.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}
