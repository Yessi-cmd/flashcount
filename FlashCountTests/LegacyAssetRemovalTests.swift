import XCTest
import SwiftData
@testable import FlashCount

/// 账户体系（`Asset`）已移除。升级和旧备份导入都必须把账户折算成资金项，
/// 一条都不能丢——否则用户打开新版就会发现钱少了。
@MainActor
final class LegacyAssetRemovalTests: XCTestCase {
    func testUpgradingFromV2ConvertsLegacyAccountsIntoCashPoolItems() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("FlashCount.store")

        // 旧库：三个账户 + 一个已有资金项，外加一笔交易用于确认其它数据不受影响。
        do {
            let configuration = ModelConfiguration(
                "FlashCount",
                schema: Schema(versionedSchema: FlashCountSchemaV2.self),
                url: storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: Schema(versionedSchema: FlashCountSchemaV2.self),
                configurations: configuration
            )
            let context = ModelContext(container)
            context.insert(Asset(name: "招商银行储蓄卡", type: .bankCard, balance: 12_000))
            context.insert(Asset(name: "花呗", type: .creditCard, balance: 3_000, note: "每月 9 号还"))
            context.insert(Asset(name: "理财通", type: .investment, balance: 5_000))
            let archived = Asset(name: "已销户的卡", type: .bankCard, balance: 100)
            archived.isArchived = true
            context.insert(archived)
            context.insert(CashPoolItem(name: "现金合计", kind: .cash, amount: 800, sortOrder: 0))
            context.insert(Transaction(amount: 42, note: "升级前交易"))
            try context.save()
        }

        let upgradedConfiguration = ModelConfiguration(
            "FlashCount",
            schema: Schema(versionedSchema: FlashCountSchemaV3.self),
            url: storeURL,
            cloudKitDatabase: .none
        )
        let upgraded = try ModelContainer(
            for: Schema(versionedSchema: FlashCountSchemaV3.self),
            migrationPlan: FlashCountMigrationPlan.self,
            configurations: upgradedConfiguration
        )
        let context = ModelContext(upgraded)

        let items = try context.fetch(FetchDescriptor<CashPoolItem>())
        XCTAssertEqual(items.count, 5, "四个账户都应折算成资金项，已有资金项保留")

        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })
        let bank = try XCTUnwrap(byName["招商银行储蓄卡"])
        XCTAssertEqual(bank.kind, .cash)
        XCTAssertEqual(bank.amount, 12_000)
        XCTAssertEqual(bank.note, "原账户类型：银行卡", "折算后必须留下原账户类型")

        let credit = try XCTUnwrap(byName["花呗"])
        XCTAssertEqual(credit.kind, .liability, "信用卡属于负债")
        XCTAssertEqual(credit.signedAmount, -3_000)
        XCTAssertEqual(credit.note, "原账户类型：信用卡 · 每月 9 号还", "原备注不能被覆盖")

        XCTAssertEqual(try XCTUnwrap(byName["理财通"]).kind, .flexibleInvestment)
        XCTAssertTrue(try XCTUnwrap(byName["已销户的卡"]).isArchived, "归档状态应保留")
        XCTAssertEqual(try XCTUnwrap(byName["现金合计"]).amount, 800)

        // 折算后的资金净额应等于原来的账户签名余额之和加上已有资金项。
        let activeNet = items.filter { !$0.isArchived }.reduce(Decimal.zero) { $0 + $1.signedAmount }
        XCTAssertEqual(activeNet, 800 + 12_000 + 5_000 - 3_000)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 1, "其它数据不受迁移影响")
    }

    func testImportingLegacyBackupConvertsAccountsAndStaysIdempotent() throws {
        let context = try makeContext()
        let service = DataBackupService(modelContext: context)

        // 造一份旧版备份：只有 assets 段，没有 cashPoolItems。
        let assetID = UUID()
        let json: [String: Any] = [
            "version": "1.9.0",
            "createdAt": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_700_000_000)),
            "assets": [[
                "id": assetID.uuidString,
                "name": "旧版银行卡",
                "type": "银行卡",
                "balance": "2500.5",
                "icon": "creditcard.fill",
                "colorHex": "#667EEA",
                "note": "",
                "isArchived": false,
                "updatedAt": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_700_000_000)),
                "createdAt": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_700_000_000))
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        _ = try service.importJSON(data: data, mode: .merge)
        let afterFirst = try context.fetch(FetchDescriptor<CashPoolItem>())
        XCTAssertEqual(afterFirst.count, 1)
        XCTAssertEqual(afterFirst.first?.name, "旧版银行卡")
        XCTAssertEqual(afterFirst.first?.kind, .cash)
        XCTAssertEqual(afterFirst.first?.amount, Decimal(string: "2500.5"))
        XCTAssertEqual(afterFirst.first?.id, assetID, "沿用账户原 UUID，重复导入才不会翻倍")

        // 同一份备份再合并一次不应产生重复条目。
        _ = try service.importJSON(data: data, mode: .merge)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CashPoolItem>()), 1)
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema(versionedSchema: FlashCountSchemaV3.self),
            configurations: configuration
        )
        return ModelContext(container)
    }
}
