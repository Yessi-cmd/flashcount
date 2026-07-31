import Foundation
import SwiftData

/// 订阅计费周期。`monthsPerCycle` 决定下次续费推进的月数，
/// `cyclesPerYear` 用于把单笔成本换算成年度等价（只做整数乘法，精确无舍入）。
enum SubscriptionBillingCycle: String, Codable, CaseIterable, Hashable, Sendable {
    case monthly = "每月"
    case quarterly = "每季度"
    case yearly = "每年"

    var monthsPerCycle: Int {
        switch self {
        case .monthly: return 1
        case .quarterly: return 3
        case .yearly: return 12
        }
    }

    var cyclesPerYear: Int {
        12 / monthsPerCycle
    }

    var displayName: String {
        rawValue
    }
}

/// 一笔订阅（Netflix、iCloud、会员、健身卡…）。
///
/// 订阅是「提醒优先」的被追踪义务：**绝不自动生成交易**。续费确认由
/// `SubscriptionService.advanceRenewal` 推进日期并默认写一笔支出——与
/// 分期账单同一条钱不变量（释放义务必须记账，否则付清看起来像多出钱）。
@Model
final class Subscription {
    var id: UUID
    var name: String
    /// 单期成本，恒为正数（AGENTS.md 金额规则）；写账时由 `isExpense` 推导符号。
    var cost: Decimal
    var billingCycle: SubscriptionBillingCycle
    var nextRenewalDate: Date
    /// 日锚点（1...31）。短月份只临时夹到月末，避免 1/31 → 2/28 → 3/28 漂移。
    var renewalDay: Int
    /// 提前几天提醒；nil = 不提醒。范围 0...90，0 归一化为 nil。
    var remindBeforeDays: Int?
    var note: String
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        cost: Decimal,
        billingCycle: SubscriptionBillingCycle,
        nextRenewalDate: Date,
        remindBeforeDays: Int? = nil,
        note: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.cost = cost
        self.billingCycle = billingCycle
        self.nextRenewalDate = nextRenewalDate
        self.renewalDay = min(
            max(Calendar.current.component(.day, from: nextRenewalDate), 1),
            31
        )
        let clamped = remindBeforeDays.map { min(max($0, 0), 90) }
        self.remindBeforeDays = clamped.flatMap { $0 == 0 ? nil : $0 }
        self.note = note
        self.isArchived = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// 下一次续费日期：走到 `monthsPerCycle` 月后的月初，把 `renewalDay`
    /// 夹到该月天数并归一到当天零点。镜像 `RecurringRule` 的锚日夹取与
    /// `InstallmentBill.repaymentDate(forInstallment:)`。
    func projectedRenewalDate(calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: nextRenewalDate)
        let currentMonth = calendar.date(
            from: DateComponents(year: components.year, month: components.month, day: 1)
        ) ?? nextRenewalDate
        let targetMonth = calendar.date(
            byAdding: .month,
            value: billingCycle.monthsPerCycle,
            to: currentMonth
        ) ?? currentMonth
        let dayRange = calendar.range(of: .day, in: .month, for: targetMonth)
        let clampedDay = min(max(renewalDay, 1), dayRange?.count ?? renewalDay)
        var targetComponents = calendar.dateComponents([.year, .month], from: targetMonth)
        targetComponents.day = clampedDay
        return calendar.startOfDay(for: calendar.date(from: targetComponents) ?? targetMonth)
    }

    /// 本次续费是否已到期（不含今天）。
    func isOverdue(asOf date: Date = Date(), calendar: Calendar = .current) -> Bool {
        nextRenewalDate < calendar.startOfDay(for: date)
    }
}
