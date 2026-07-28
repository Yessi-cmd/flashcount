import Foundation

// MARK: - 备份校验

extension DataBackupService {
    private struct SemanticVersion: Comparable {
        let major: Int
        let minor: Int
        let patch: Int

        init?(_ rawValue: String) {
            let parts = rawValue.split(separator: ".", omittingEmptySubsequences: false)
            guard (2...3).contains(parts.count),
                  let major = Int(parts[0]),
                  let minor = Int(parts[1]) else {
                return nil
            }
            let patch: Int
            if parts.count == 3 {
                guard let parsedPatch = Int(parts[2]) else { return nil }
                patch = parsedPatch
            } else {
                patch = 0
            }
            guard major >= 0, minor >= 0, patch >= 0 else { return nil }
            self.major = major
            self.minor = minor
            self.patch = patch
        }

        static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
            (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
    }

    static func validateVersion(_ rawVersion: String) throws {
        guard let version = SemanticVersion(rawVersion),
              let minimum = SemanticVersion(minimumSupportedBackupVersion),
              let current = SemanticVersion(currentBackupVersion) else {
            throw ImportError.invalidVersion(rawVersion)
        }
        guard version >= minimum, version <= current else {
            throw ImportError.unsupportedVersion(rawVersion)
        }
    }

    static func validateContents(_ backup: BackupData, mode: ImportMode) throws {
        try validateUniqueIDs(backup.categories.map(\.id), label: "分类")
        try validateUniqueIDs(backup.ledgers.map(\.id), label: "账本")
        try validateUniqueIDs(backup.transactions.map(\.id), label: "账单")
        try validateUniqueIDs(backup.assets.map(\.id), label: "账户")
        try validateUniqueIDs(backup.physicalAssets.map(\.id), label: "实物资产")
        try validateUniqueIDs(backup.recurringRules.map(\.id), label: "周期规则")
        try validateUniqueIDs(backup.recurringOccurrences.map(\.id), label: "周期发生项")
        try validateUniqueIDs(backup.budgets.map(\.id), label: "预算")
        try validateUniqueIDs(backup.cashPoolItems.map(\.id), label: "资金项")
        try validateUniqueIDs(backup.cashPoolStates.map(\.id), label: "资金状态")
        try validateUniqueIDs(backup.installmentBills.map(\.id), label: "分期")
        try validateUniqueIDs(backup.savingsGoals.map(\.id), label: "储蓄目标")
        try validateUniqueIDs(backup.templates.map(\.id), label: "模板")
        try validateUniqueIDs(backup.reminders.map { $0.id.uuidString }, label: "提醒")

        guard backup.transactions.allSatisfy({ $0.amount.decimalValue > 0 }) else {
            throw ImportError.invalidContents("账单金额必须大于零")
        }
        guard backup.assets.allSatisfy({ $0.balance.decimalValue >= 0 }) else {
            throw ImportError.invalidContents("账户余额不能为负数")
        }
        guard backup.physicalAssets.allSatisfy({ dto in
            let purchase = dto.purchasePrice.decimalValue
            let salvage = dto.salvageValue.decimalValue
            return purchase > 0 && salvage >= 0 && salvage <= purchase
                && dto.targetDailyCost.decimalValue > 0
                && (dto.soldPrice?.decimalValue ?? 0) >= 0
        }) else {
            throw ImportError.invalidContents("实物资产金额超出有效范围")
        }
        guard backup.recurringRules.allSatisfy({ $0.amount.decimalValue > 0 }),
              backup.budgets.allSatisfy({ $0.monthlyLimit.decimalValue > 0 }),
              backup.cashPoolItems.allSatisfy({ $0.amount.decimalValue >= 0 }),
              backup.installmentBills.allSatisfy({ $0.totalAmount.decimalValue > 0 }),
              backup.savingsGoals.allSatisfy({ $0.targetAmount.decimalValue > 0 && $0.currentAmount.decimalValue >= 0 }),
              backup.templates.allSatisfy({ $0.amount.decimalValue > 0 }) else {
            throw ImportError.invalidContents("存在不符合业务约束的金额")
        }

        if mode == .replace {
            let categoryIDs = Set(try backup.categories.map {
                try validatedUUID($0.id, label: "分类")
            })
            let ledgerIDs = Set(try backup.ledgers.map {
                try validatedUUID($0.id, label: "账本")
            })
            let recurringRuleIDs = Set(try backup.recurringRules.map {
                try validatedUUID($0.id, label: "周期规则")
            })
            let categoryReferences = try (backup.transactions.compactMap(\.categoryId)
                + backup.recurringRules.compactMap(\.categoryId)
                + backup.categories.compactMap(\.mergedIntoCategoryId))
                .map { try validatedUUID($0, label: "分类关系引用") }
            let ledgerReferences = try (backup.transactions.compactMap(\.ledgerId)
                + backup.recurringRules.compactMap(\.ledgerId)
                + backup.budgets.compactMap(\.ledgerId))
                .map { try validatedUUID($0, label: "账本关系引用") }
            let recurringRuleReferences = try backup.transactions.compactMap(\.recurringRuleId)
                .map { try validatedUUID($0, label: "周期规则关系引用") }
            let occurrenceRuleReferences = try backup.recurringOccurrences.compactMap(\.ruleId)
                .map { try validatedUUID($0, label: "周期发生项规则引用") }
            let occurrenceTransactionReferences = try backup.recurringOccurrences.compactMap(\.transactionId)
                .map { try validatedUUID($0, label: "周期发生项交易引用") }
            guard categoryReferences.allSatisfy(categoryIDs.contains) else {
                throw ImportError.invalidContents("分类关系引用不存在")
            }
            guard ledgerReferences.allSatisfy(ledgerIDs.contains) else {
                throw ImportError.invalidContents("账本关系引用不存在")
            }
            guard recurringRuleReferences.allSatisfy(recurringRuleIDs.contains) else {
                throw ImportError.invalidContents("周期规则关系引用不存在")
            }
            guard occurrenceRuleReferences.allSatisfy(recurringRuleIDs.contains) else {
                throw ImportError.invalidContents("周期发生项规则引用不存在")
            }
            let transactionIDs = Set(try backup.transactions.map {
                try validatedUUID($0.id, label: "账单")
            })
            guard occurrenceTransactionReferences.allSatisfy(transactionIDs.contains) else {
                throw ImportError.invalidContents("周期发生项交易引用不存在")
            }
        }
    }

    private static func validateUniqueIDs(_ ids: [String], label: String) throws {
        guard ids.allSatisfy({ UUID(uuidString: $0) != nil }) else {
            throw ImportError.invalidContents("\(label)包含无效 UUID")
        }
        guard Set(ids.compactMap(UUID.init(uuidString:))).count == ids.count else {
            throw ImportError.invalidContents("\(label)包含重复 UUID")
        }
    }

    /// Parses untrusted backup IDs without turning malformed input into a crash.
    static func validatedUUID(_ rawValue: String, label: String) throws -> UUID {
        guard let id = UUID(uuidString: rawValue) else {
            throw ImportError.invalidContents("\(label)包含无效 UUID")
        }
        return id
    }
}
