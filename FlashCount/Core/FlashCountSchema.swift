import Foundation
import SwiftData

/// The first explicitly versioned schema. Keeping the current model set in a
/// named version lets future releases migrate data forward without relying on
/// an implicit store shape or deleting a user's local ledger on failure.
enum FlashCountSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
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
            TransactionTemplate.self,
            Reminder.self
        ]
    }
}

/// Adds persisted recurring occurrences without changing the existing financial
/// model fields. This keeps the migration lightweight and preserves old stores.
enum FlashCountSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Transaction.self,
            Category.self,
            Ledger.self,
            RecurringRule.self,
            RecurringOccurrence.self,
            Budget.self,
            Asset.self,
            PhysicalAsset.self,
            CashPoolItem.self,
            CashPoolState.self,
            SavingsGoal.self,
            InstallmentBill.self,
            TransactionTemplate.self,
            Reminder.self
        ]
    }
}

/// 移除历史「账户」模型（`Asset`）。它与资金池语义重叠却被净资产直接相加，
/// 且从无新建入口。V2→V3 的自定义迁移会先把每个账户折算成资金项再删除，
/// 因此升级不会丢数据——净资产口径也就此收敛为资金池一条。
enum FlashCountSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Transaction.self,
            Category.self,
            Ledger.self,
            RecurringRule.self,
            RecurringOccurrence.self,
            Budget.self,
            PhysicalAsset.self,
            CashPoolItem.self,
            CashPoolState.self,
            SavingsGoal.self,
            InstallmentBill.self,
            TransactionTemplate.self,
            Reminder.self
        ]
    }
}

enum FlashCountMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FlashCountSchemaV1.self, FlashCountSchemaV2.self, FlashCountSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: FlashCountSchemaV1.self, toVersion: FlashCountSchemaV2.self),
            .custom(
                fromVersion: FlashCountSchemaV2.self,
                toVersion: FlashCountSchemaV3.self,
                willMigrate: { context in
                    // 仍在 V2 结构下执行，此时 Asset 还能读取。
                    try convertLegacyAccountsToCashPoolItems(in: context)
                },
                didMigrate: nil
            )
        ]
    }

    /// 把历史账户逐条折算成资金项，然后删除账户本体。
    /// 排序号接在既有资金项之后，避免与用户已有条目抢位置。
    static func convertLegacyAccountsToCashPoolItems(in context: ModelContext) throws {
        let assets = try context.fetch(FetchDescriptor<Asset>(
            sortBy: [SortDescriptor(\Asset.createdAt)]
        ))
        guard !assets.isEmpty else { return }

        let existingItems = try context.fetch(FetchDescriptor<CashPoolItem>())
        var nextSortOrder = (existingItems.map(\.sortOrder).max() ?? -1) + 1

        for asset in assets {
            context.insert(LegacyAssetConversion.makeCashPoolItem(
                name: asset.name,
                rawType: asset.type.rawValue,
                balance: asset.balance,
                existingNote: asset.note,
                isArchived: asset.isArchived,
                createdAt: asset.createdAt,
                updatedAt: asset.updatedAt,
                sortOrder: nextSortOrder
            ))
            nextSortOrder += 1
            context.delete(asset)
        }
        try context.save()
    }
}
