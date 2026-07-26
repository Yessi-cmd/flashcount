import SwiftUI

/// 体检覆盖的问题类型。顺序即界面上的展示顺序。
enum DataHealthIssueKind: String, CaseIterable, Identifiable, Equatable {
    case duplicateUUID
    case orphanBudget
    case emptyTransactionDelta
    case duplicateCashPoolState
    case missingLedger
    case uncategorizedTransaction
    case invalidTransactionAmount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .duplicateUUID: return "重复 UUID"
        case .orphanBudget: return "孤儿预算"
        case .emptyTransactionDelta: return "空 delta"
        case .duplicateCashPoolState: return "重复资金池状态"
        case .missingLedger: return "缺失账本"
        case .uncategorizedTransaction: return "未分类交易"
        case .invalidTransactionAmount: return "无效交易金额"
        }
    }

    var icon: String {
        switch self {
        case .duplicateUUID: return "square.stack.3d.up"
        case .orphanBudget: return "questionmark.folder"
        case .emptyTransactionDelta: return "arrow.left.arrow.right"
        case .duplicateCashPoolState: return "wallet.pass"
        case .missingLedger: return "book.closed"
        case .uncategorizedTransaction: return "tag"
        case .invalidTransactionAmount: return "exclamationmark.triangle"
        }
    }

    var accent: Color {
        switch self {
        case .missingLedger, .emptyTransactionDelta, .duplicateCashPoolState:
            return DesignSystem.primaryColor
        case .duplicateUUID, .orphanBudget, .invalidTransactionAmount:
            return DesignSystem.warningColor
        case .uncategorizedTransaction:
            return DesignSystem.textSecondary
        }
    }
}
