import XCTest
import SwiftData
@testable import FlashCount

// MARK: - 备份导入导出

extension FinanceDomainTests {
    func testDuplicateBackupUUIDIsRejectedBeforeReplaceMutatesData() throws {
        let context = try makeContext()
        context.insert(Transaction(amount: 10))
        context.insert(Transaction(amount: 20))
        try context.save()
        let service = DataBackupService(modelContext: context)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: service.exportJSON()) as? [String: Any])
        var transactions = try XCTUnwrap(json["transactions"] as? [[String: Any]])
        let duplicateID = try XCTUnwrap(transactions[0]["id"] as? String)
        transactions[0]["id"] = duplicateID.lowercased()
        transactions[1]["id"] = duplicateID.uppercased()
        json["transactions"] = transactions
        let invalidBackup = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try service.importJSON(data: invalidBackup, mode: .replace))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 2)
    }

    func testLegacyBackupWithoutCashPoolDeltaRemainsEditableAndDeletable() throws {
        let context = try makeContext()
        let ledger = Ledger.defaultLedgers()[0]
        let transaction = Transaction(amount: 10, note: "旧备份", cashPoolDelta: -10, ledger: ledger)
        context.insert(ledger)
        context.insert(transaction)
        context.insert(CashPoolState(transactionDelta: -10))
        try context.save()

        let backup = DataBackupService(modelContext: context)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: backup.exportJSON()) as? [String: Any])
        var transactions = try XCTUnwrap(json["transactions"] as? [[String: Any]])
        transactions[0].removeValue(forKey: "cashPoolDelta")
        json["transactions"] = transactions

        _ = try backup.importJSON(
            data: JSONSerialization.data(withJSONObject: json),
            mode: .replace
        )

        let restored = try XCTUnwrap(context.fetch(FetchDescriptor<Transaction>()).first)
        XCTAssertEqual(restored.cashPoolDelta, -10)
        let mutation = TransactionMutationService(modelContext: context)
        try mutation.update(restored, with: TransactionDraft(amount: 20, isExpense: true, ledger: restored.ledger))
        XCTAssertEqual(try context.fetch(FetchDescriptor<CashPoolState>()).first?.transactionDelta, -20)
        try mutation.delete(restored)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CashPoolState>()).first?.transactionDelta, 0)
    }

    func testMergedDuplicateCategoryRemapsImportedBudgetToLocalCategory() throws {
        let source = try makeContext()
        let sourceCategory = Category(name: "预算测试分类", icon: "tag.fill", colorHex: "#123456")
        let sourceBudget = Budget(monthlyLimit: 500, year: 2026, month: 7, categoryId: sourceCategory.id)
        source.insert(sourceCategory)
        source.insert(sourceBudget)
        try source.save()
        let snapshot = try DataBackupService(modelContext: source).exportJSON()

        let destination = try makeContext()
        let localCategory = Category(name: "预算测试分类", icon: "tag.fill", colorHex: "#654321")
        destination.insert(localCategory)
        try destination.save()

        _ = try DataBackupService(modelContext: destination).importJSON(data: snapshot, mode: .merge)
        let budget = try XCTUnwrap(destination.fetch(FetchDescriptor<Budget>()).first)
        XCTAssertEqual(budget.categoryId, localCategory.id)
    }

    func testBackupRoundTripPreservesTimestampsAndRecurringRelationship() throws {
        let context = try makeContext()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let ledger = Ledger.defaultLedgers()[0]
        ledger.createdAt = timestamp
        let asset = Asset(name: "账户", type: .cash, balance: 12)
        asset.createdAt = timestamp
        asset.updatedAt = timestamp.addingTimeInterval(10)
        let rule = RecurringRule(title: "订阅", amount: 8, nextDueDate: timestamp, ledger: ledger)
        rule.createdAt = timestamp.addingTimeInterval(20)
        let transaction = Transaction(amount: 8, note: "关联", date: timestamp, cashPoolDelta: -8, ledger: ledger, recurringRule: rule)
        transaction.createdAt = timestamp.addingTimeInterval(30)
        let occurrence = RecurringOccurrence(
            occurrenceKey: RecurringOccurrence.key(ruleID: rule.id, scheduledDate: timestamp),
            ruleID: rule.id,
            transactionID: transaction.id,
            scheduledDate: timestamp,
            actualDate: timestamp,
            amount: 8,
            isExpense: true,
            title: rule.title,
            note: transaction.note,
            ledgerID: ledger.id,
            status: .generated,
            createdAt: timestamp.addingTimeInterval(35),
            resolvedAt: timestamp.addingTimeInterval(40)
        )
        let budget = Budget(monthlyLimit: 300, year: 2026, month: 7, ledger: ledger)
        budget.createdAt = timestamp.addingTimeInterval(40)
        let expectedLedgerCreatedAt = ledger.createdAt
        let expectedAssetCreatedAt = asset.createdAt
        let expectedAssetUpdatedAt = asset.updatedAt
        let expectedRuleCreatedAt = rule.createdAt
        let expectedTransactionCreatedAt = transaction.createdAt
        let expectedBudgetCreatedAt = budget.createdAt
        context.insert(ledger)
        context.insert(asset)
        context.insert(rule)
        context.insert(transaction)
        context.insert(occurrence)
        context.insert(budget)
        context.insert(CashPoolState(transactionDelta: -8))
        try context.save()

        let snapshot = try DataBackupService(modelContext: context).exportJSON()
        _ = try DataBackupService(modelContext: context).importJSON(data: snapshot, mode: .replace)

        let restoredLedger = try XCTUnwrap(context.fetch(FetchDescriptor<Ledger>()).first { $0.name == ledger.name })
        let restoredAsset = try XCTUnwrap(context.fetch(FetchDescriptor<Asset>()).first { $0.name == asset.name })
        let restoredRule = try XCTUnwrap(context.fetch(FetchDescriptor<RecurringRule>()).first { $0.title == rule.title })
        let restoredTransaction = try XCTUnwrap(context.fetch(FetchDescriptor<Transaction>()).first { $0.note == transaction.note })
        let restoredOccurrence = try XCTUnwrap(context.fetch(FetchDescriptor<RecurringOccurrence>()).first)
        let restoredBudget = try XCTUnwrap(context.fetch(FetchDescriptor<Budget>()).first { $0.monthlyLimit == 300 })
        XCTAssertEqual(restoredLedger.createdAt, expectedLedgerCreatedAt)
        XCTAssertEqual(restoredAsset.createdAt, expectedAssetCreatedAt)
        XCTAssertEqual(restoredAsset.updatedAt, expectedAssetUpdatedAt)
        XCTAssertEqual(restoredRule.createdAt, expectedRuleCreatedAt)
        XCTAssertEqual(restoredTransaction.createdAt, expectedTransactionCreatedAt)
        XCTAssertEqual(restoredTransaction.recurringRule?.id, restoredRule.id)
        XCTAssertEqual(restoredOccurrence.occurrenceKey, occurrence.occurrenceKey)
        XCTAssertEqual(restoredOccurrence.transactionID, restoredTransaction.id)
        XCTAssertEqual(restoredOccurrence.status, .generated)
        XCTAssertEqual(restoredBudget.createdAt, expectedBudgetCreatedAt)
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
}
