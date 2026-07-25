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

enum FlashCountMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [FlashCountSchemaV1.self, FlashCountSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: FlashCountSchemaV1.self, toVersion: FlashCountSchemaV2.self)]
    }
}
