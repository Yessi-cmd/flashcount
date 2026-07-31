import XCTest
import SwiftData
@testable import FlashCount

// MARK: - 提醒迁移与 Schema 升级

extension FinanceDomainTests {
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

    func testCorruptedLegacyReminderFileDoesNotMarkMigrationComplete() throws {
        let context = try makeContext()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("flashcount-reminders.json")
        try Data("not-json".utf8).write(to: fileURL)
        let suiteName = "ReminderCorruptionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let migrationKey = "test-reminder-corruption"
        let service = ReminderDataService(
            modelContext: context,
            legacyStore: FileReminderStore(fileURL: fileURL),
            userDefaults: defaults,
            migrationKey: migrationKey
        )

        XCTAssertThrowsError(try service.migrateLegacyFileIfNeeded())
        XCTAssertFalse(defaults.bool(forKey: migrationKey))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Reminder>()), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
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
            schema: Schema(legacyModelTypes + [Reminder.self, RecurringOccurrence.self]),
            url: storeURL,
            cloudKitDatabase: .none
        )
        let upgradedContainer = try ModelContainer(
            for: Transaction.self,
            Category.self,
            Ledger.self,
            RecurringRule.self,
            Budget.self,
            PhysicalAsset.self,
            CashPoolItem.self,
            CashPoolState.self,
            SavingsGoal.self,
            InstallmentBill.self,
            TransactionTemplate.self,
            Reminder.self,
            RecurringOccurrence.self,
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

    func testVersionedSchemaMigrationAddsRecurringOccurrencesWithoutDroppingTransactions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("FlashCount.store")

        let original = Transaction(amount: 88, note: "V1 交易")
        let originalID = original.id
        do {
            let configuration = ModelConfiguration(
                "FlashCount",
                schema: Schema(versionedSchema: FlashCountSchemaV1.self),
                url: storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: Schema(versionedSchema: FlashCountSchemaV1.self),
                configurations: configuration
            )
            let context = ModelContext(container)
            context.insert(original)
            try context.save()
        }

        let upgradedConfiguration = ModelConfiguration(
            "FlashCount",
            schema: Schema(versionedSchema: FlashCountSchemaV3.self),
            url: storeURL,
            cloudKitDatabase: .none
        )
        let upgradedContainer = try ModelContainer(
            for: Schema(versionedSchema: FlashCountSchemaV3.self),
            migrationPlan: FlashCountMigrationPlan.self,
            configurations: upgradedConfiguration
        )
        let upgradedContext = ModelContext(upgradedContainer)

        let restored = try XCTUnwrap(upgradedContext.fetch(FetchDescriptor<Transaction>()).first)
        XCTAssertEqual(restored.id, originalID)
        XCTAssertEqual(restored.amount, 88)
        XCTAssertEqual(try upgradedContext.fetchCount(FetchDescriptor<RecurringOccurrence>()), 0)
    }

    /// V3 → V4 是纯增模型（`Subscription`）的轻量迁移：既有数据必须原样保留，
    /// 新模型在旧库上打开时计数为 0。
    func testVersionedSchemaV3ToV4MigrationAddsSubscriptionsWithoutDroppingTransactions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("FlashCount.store")

        let original = Transaction(amount: 88, note: "V3 交易")
        let originalID = original.id
        do {
            let configuration = ModelConfiguration(
                "FlashCount",
                schema: Schema(versionedSchema: FlashCountSchemaV3.self),
                url: storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: Schema(versionedSchema: FlashCountSchemaV3.self),
                configurations: configuration
            )
            let context = ModelContext(container)
            context.insert(original)
            try context.save()
        }

        let upgradedConfiguration = ModelConfiguration(
            "FlashCount",
            schema: Schema(versionedSchema: FlashCountSchemaV4.self),
            url: storeURL,
            cloudKitDatabase: .none
        )
        let upgradedContainer = try ModelContainer(
            for: Schema(versionedSchema: FlashCountSchemaV4.self),
            migrationPlan: FlashCountMigrationPlan.self,
            configurations: upgradedConfiguration
        )
        let upgradedContext = ModelContext(upgradedContainer)

        let restored = try XCTUnwrap(upgradedContext.fetch(FetchDescriptor<Transaction>()).first)
        XCTAssertEqual(restored.id, originalID)
        XCTAssertEqual(restored.amount, 88)
        XCTAssertEqual(try upgradedContext.fetchCount(FetchDescriptor<Subscription>()), 0)
    }
}
