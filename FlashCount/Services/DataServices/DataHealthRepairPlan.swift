import Foundation
import SwiftData

protocol DataHealthIdentifiedModel: AnyObject {
    var id: UUID { get set }
}

extension Transaction: DataHealthIdentifiedModel {}
extension Category: DataHealthIdentifiedModel {}
extension Ledger: DataHealthIdentifiedModel {}
extension RecurringRule: DataHealthIdentifiedModel {}
extension RecurringOccurrence: DataHealthIdentifiedModel {}
extension Budget: DataHealthIdentifiedModel {}
extension PhysicalAsset: DataHealthIdentifiedModel {}
extension CashPoolItem: DataHealthIdentifiedModel {}
extension CashPoolState: DataHealthIdentifiedModel {}
extension SavingsGoal: DataHealthIdentifiedModel {}
extension InstallmentBill: DataHealthIdentifiedModel {}
extension TransactionTemplate: DataHealthIdentifiedModel {}
extension Reminder: DataHealthIdentifiedModel {}

enum DataHealthRecordType: String, Hashable {
    case transaction = "交易"
    case category = "分类"
    case ledger = "账本"
    case recurringRule = "周期规则"
    case recurringOccurrence = "周期发生项"
    case budget = "预算"
    case physicalAsset = "实物资产"
    case cashPoolItem = "资金项"
    case savingsGoal = "储蓄目标"
    case installmentBill = "分期账单"
    case transactionTemplate = "记账模板"
    case reminder = "提醒"
}

struct DataHealthRekeyAction {
    let recordType: DataHealthRecordType
    let object: any DataHealthIdentifiedModel
    let newID: UUID
}

struct DataHealthLedgerAction {
    let transaction: Transaction
    let ledger: Ledger
}

struct DataHealthDeltaAction {
    let transaction: Transaction
    let value: Decimal
}

struct DataHealthStateUpdateAction {
    let state: CashPoolState
    let value: Decimal
}

struct DataHealthRepairPlan {
    let fingerprint: String
    let rekeyActions: [DataHealthRekeyAction]
    let ledgerActions: [DataHealthLedgerAction]
    let deltaActions: [DataHealthDeltaAction]
    let stateUpdate: DataHealthStateUpdateAction?
    let newStateValue: Decimal?
    let duplicateStatesToDelete: [CashPoolState]
    let defaultLedgerToInsert: Ledger?

    var actionCount: Int {
        rekeyActions.count
            + ledgerActions.count
            + deltaActions.count
            + (stateUpdate == nil && newStateValue == nil ? 0 : 1)
            + duplicateStatesToDelete.count
            + (defaultLedgerToInsert == nil ? 0 : 1)
    }

    var hasChanges: Bool { actionCount > 0 }
}
