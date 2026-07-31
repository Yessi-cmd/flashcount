import Foundation
import SwiftData

/// 订阅合计的纯聚合，抽离出视图以便测试（镜像 `AssetPortfolioSnapshot`）。
///
/// 钱正确性：每项先算年度等价（`cost × cyclesPerYear`，只做整数乘法，精确），
/// 求和得到 `yearlyTotal`，**全库只除这一次**得到 `monthlyTotal`。逐项除再求和
/// 会把舍入误差放大（违反「先乘后除」的钱规则），且每月/每年显示会不一致。
struct SubscriptionAggregation: Equatable {
    let count: Int
    let monthlyTotal: Decimal
    let yearlyTotal: Decimal
    let nextRenewalDate: Date?
    let nextRenewalName: String?

    init(subscriptions: [Subscription], asOf: Date = Date(), calendar: Calendar = .current) {
        let active = subscriptions.filter { !$0.isArchived }
        self.count = active.count

        let yearlySum = active.reduce(Decimal.zero) { total, subscription in
            total + subscription.cost * Decimal(subscription.billingCycle.cyclesPerYear)
        }
        self.yearlyTotal = yearlySum
        self.monthlyTotal = yearlySum / Decimal(12)

        // 已到期的订阅也是「下一个要续费」的候选，因此不过滤未来日期。
        let next = active.min { $0.nextRenewalDate < $1.nextRenewalDate }
        self.nextRenewalDate = next?.nextRenewalDate
        self.nextRenewalName = next?.name
    }
}

/// 订阅的读写与续费推进。
///
/// 订阅是提醒优先的义务，**绝不自动生成交易**。续费确认（`advanceRenewal`）
/// 推进下次续费日期，并默认写一笔支出——释放义务必须记账，否则付清看起来像
/// 多出钱（与分期账单同一条不变量）。所有写路径在同一事务边界刷新
/// `SubscriptionRenewalSnapshotStore`，保证通知排期数据不过期。
@MainActor
final class SubscriptionService {
    /// 新建 / 编辑订阅。
    struct Draft {
        let name: String
        let cost: Decimal
        let billingCycle: SubscriptionBillingCycle
        let nextRenewalDate: Date
        let remindBeforeDays: Int?
        let note: String

        init(
            name: String,
            cost: Decimal,
            billingCycle: SubscriptionBillingCycle,
            nextRenewalDate: Date,
            remindBeforeDays: Int? = nil,
            note: String = ""
        ) {
            self.name = name
            self.cost = cost
            self.billingCycle = billingCycle
            self.nextRenewalDate = nextRenewalDate
            self.remindBeforeDays = remindBeforeDays
            self.note = note
        }
    }

    /// 确认续费。
    struct RenewalDraft {
        let date: Date
        let category: Category?
        /// 是否同时生成支出交易。已在账本手记过的用户可以关掉，避免重复计一笔。
        let recordsTransaction: Bool

        init(date: Date = Date(), category: Category? = nil, recordsTransaction: Bool = true) {
            self.date = date
            self.category = category
            self.recordsTransaction = recordsTransaction
        }
    }

    enum SubscriptionError: LocalizedError {
        case invalidName
        case invalidCost
        case alreadyArchived

        var errorDescription: String? {
            switch self {
            case .invalidName: return "订阅名称不能为空"
            case .invalidCost: return "订阅金额必须大于零"
            case .alreadyArchived: return "这笔订阅已归档"
            }
        }
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func add(_ draft: Draft) throws -> Subscription {
        let subscription = try makeSubscription(from: draft)
        do {
            modelContext.insert(subscription)
            try commitAndRefreshSnapshot()
            return subscription
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func update(_ subscription: Subscription, draft: Draft) throws {
        guard !subscription.isArchived else { throw SubscriptionError.alreadyArchived }
        apply(draft, to: subscription)
        subscription.updatedAt = Date()
        do {
            try commitAndRefreshSnapshot()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func archive(_ subscription: Subscription) throws {
        guard !subscription.isArchived else { return }
        subscription.isArchived = true
        subscription.updatedAt = Date()
        do {
            try commitAndRefreshSnapshot()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// 标记一次续费完成：推进下次续费日期，并默认写一笔支出。
    /// 日期推进与支出交易在同一次提交里完成，任何一步失败都整体回滚。
    /// 金额固定为 `subscription.cost`——价格变了先编辑订阅，续费金额不该有歧义。
    @discardableResult
    func advanceRenewal(_ subscription: Subscription, draft: RenewalDraft) throws -> Transaction? {
        guard !subscription.isArchived else { throw SubscriptionError.alreadyArchived }

        do {
            var created: Transaction?
            if draft.recordsTransaction {
                let transaction = Transaction(
                    amount: subscription.cost,
                    isExpense: true,
                    note: "\(subscription.name) 续费",
                    date: draft.date,
                    category: draft.category,
                    ledger: try defaultLedger()
                )
                let delta = CashPoolService.transactionDelta(for: transaction)
                transaction.cashPoolDelta = delta
                modelContext.insert(transaction)
                try CashPoolService(modelContext: modelContext).apply(delta: delta)
                created = transaction
            }

            subscription.nextRenewalDate = subscription.projectedRenewalDate()
            subscription.updatedAt = Date()

            try commitAndRefreshSnapshot()
            return created
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    // MARK: - Private

    private func makeSubscription(from draft: Draft) throws -> Subscription {
        try validate(draft)
        return Subscription(
            name: draft.name,
            cost: draft.cost,
            billingCycle: draft.billingCycle,
            nextRenewalDate: draft.nextRenewalDate,
            remindBeforeDays: draft.remindBeforeDays,
            note: draft.note
        )
    }

    private func apply(_ draft: Draft, to subscription: Subscription) {
        subscription.name = draft.name
        subscription.cost = draft.cost
        subscription.billingCycle = draft.billingCycle
        subscription.nextRenewalDate = draft.nextRenewalDate
        subscription.renewalDay = min(
            max(Calendar.current.component(.day, from: draft.nextRenewalDate), 1),
            31
        )
        let clamped = draft.remindBeforeDays.map { min(max($0, 0), 90) }
        subscription.remindBeforeDays = clamped.flatMap { $0 == 0 ? nil : $0 }
        subscription.note = draft.note
    }

    private func validate(_ draft: Draft) throws {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SubscriptionError.invalidName
        }
        guard draft.cost > 0 else { throw SubscriptionError.invalidCost }
    }

    private func commitAndRefreshSnapshot() throws {
        try modelContext.save()
        let all = try modelContext.fetch(FetchDescriptor<Subscription>())
        SubscriptionRenewalSnapshotStore.refresh(from: all)
    }

    private func defaultLedger() throws -> Ledger? {
        let ledgers = try modelContext.fetch(FetchDescriptor<Ledger>(sortBy: [SortDescriptor(\Ledger.sortOrder)]))
        return ledgers.first(where: { $0.isDefault }) ?? ledgers.first
    }
}
