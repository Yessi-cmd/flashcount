import Foundation
import SwiftData

/// 预算预警等级
enum BudgetAlertLevel: String, Codable {
    case healthy = "健康"      // < 80%
    case warning = "注意"      // 80% ~ 100%
    case danger = "危险"       // > 100%

    var emoji: String {
        switch self {
        case .healthy: return "🟢"
        case .warning: return "🟡"
        case .danger: return "🔴"
        }
    }

    var message: String {
        switch self {
        case .healthy: return "预算充裕，继续保持！"
        case .warning: return "注意控制开支，即将触及预算线"
        case .danger: return "按目前进度，你月底要吃土了！"
        }
    }
}

/// 预算（按账本 + 可选分类）
@Model
final class Budget {
    var id: UUID
    var monthlyLimit: Decimal   // 月度预算上限
    var year: Int               // 预算年份
    var month: Int              // 预算月份 (1-12)
    var createdAt: Date

    // 关系：属于哪个账本
    var ledger: Ledger?
    // 可选：针对某个分类的子预算（nil = 账本总预算）
    var categoryId: UUID?

    init(
        monthlyLimit: Decimal,
        year: Int,
        month: Int,
        ledger: Ledger? = nil,
        categoryId: UUID? = nil
    ) {
        self.id = UUID()
        self.monthlyLimit = monthlyLimit
        self.year = year
        self.month = month
        self.createdAt = Date()
        self.ledger = ledger
        self.categoryId = categoryId
    }
}
