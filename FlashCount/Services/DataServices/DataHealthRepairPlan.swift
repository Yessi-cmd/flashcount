import Foundation
import SwiftData

/// 带可写 `id` 的模型。重复 UUID 的修复手段就是重新编号，因此 `id`
/// 必须可写；所有持久化模型都符合。
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

/// 体检报告里指代的记录类型，`rawValue` 直接作为界面上的中文名。
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

/// 一次重新编号：把某条记录的 UUID 换成新的。
/// 只在没有其他数据按原 ID 引用它时才生成，否则会改变引用关系。
struct DataHealthRekeyAction {
    let recordType: DataHealthRecordType
    let object: any DataHealthIdentifiedModel
    let newID: UUID
}

/// 一次账本归属修复：把无账本的交易挂到主账本上。
struct DataHealthLedgerAction {
    let transaction: Transaction
    let ledger: Ledger
}

/// 一次资金增减补写：给缺 `cashPoolDelta` 的交易补上它对现金的影响。
struct DataHealthDeltaAction {
    let transaction: Transaction
    let value: Decimal
}

/// 一次资金池状态改写：把累计增减对齐到重算结果。
struct DataHealthStateUpdateAction {
    let state: CashPoolState
    let value: Decimal
}

/// 一次体检得出的完整修复方案，以及生成它时的数据指纹。
///
/// `apply` 会重新体检并比对 `fingerprint`：预览之后数据只要变过一处就拒绝
/// 执行（`DataHealthError.stalePreview`）——否则修复会落在用户已经改过的
/// 数据上，而用户看到的预览描述的是另一份数据。
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
