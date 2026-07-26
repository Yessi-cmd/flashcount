import SwiftUI
import SwiftData

struct ReportPageData {
    let report: ReportData
    let budget: ReportBudgetSnapshotValue
}

enum ReportLoadState {
    case loading
    case refreshing(ReportPageData)
    case loaded(ReportPageData)
    case empty(ReportPageData)
    case failed(String)

    var visibleData: ReportPageData? {
        switch self {
        case .refreshing(let data), .loaded(let data), .empty(let data): return data
        case .loading, .failed: return nil
        }
    }
}

private struct GenerationKey: Hashable {
    let isActive: Bool
    let digest: Int
    let retry: Int
    let weekendBudgetMultiplierPercent: Int
    let period: ReportPeriod
    let payday: Int
    let targetKind: String
    let targetReferenceDate: Date
}

/// 报表内容区：观察范围内的交易与预算，驱动加载状态机并渲染各卡片。
/// 卡片实现拆分在 `Cards/ReportSummaryCards.swift` 与 `Cards/ReportChartCards.swift`。
struct ReportObservedContent: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var privacyLock: PrivacyLockService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var observedTransactions: [Transaction]
    @Query(sort: \Budget.createdAt) private var budgets: [Budget]
    /// 分类表很小，单独观察它。分类改名/换图标/换颜色同样会改变报表，
    /// 但那是分类自己的属性——没必要在每一笔交易上重复哈希一遍。
    @Query private var categories: [Category]

    /// 报表 Tab 是否在前台。TabView 会保活页面，若不看这个标记，
    /// 用户在账本页每记一笔都会在后台把整份报表重算一遍。
    let isActive: Bool
    let scope: ReportObservationScope
    let period: ReportPeriod
    let target: ReportTarget
    let payday: Int
    let weekendBudgetMultiplierPercent: Int

    @State private var state: ReportLoadState = .loading
    @State private var retryToken = 0
    @State var selectedBucketID: Date?
    @State var showChartDetails = false
    @State var drillDown: ReportDrillDownRequest?
    @State private var generationToken: UUID?

    init(
        isActive: Bool = true,
        scope: ReportObservationScope,
        period: ReportPeriod,
        target: ReportTarget,
        payday: Int,
        weekendBudgetMultiplierPercent: Int
    ) {
        self.isActive = isActive
        self.scope = scope
        self.period = period
        self.target = target
        self.payday = payday
        self.weekendBudgetMultiplierPercent = weekendBudgetMultiplierPercent
        let start = scope.start
        let end = scope.end
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { transaction in
                transaction.date >= start && transaction.date < end
            },
            sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
        )
        // 变更侦测要读每笔交易的分类，不预取就是一条一条 fault，年报下尤其明显。
        descriptor.relationshipKeyPathsForPrefetching = [\Transaction.category]
        _observedTransactions = Query(descriptor)
    }

    private var weekendBudgetMultiplier: Decimal {
        WeekendBudgetPreferences.multiplier(for: weekendBudgetMultiplierPercent)
    }

    private var transactionDigest: Int {
        var hasher = Hasher()
        for transaction in observedTransactions {
            hasher.combine(transaction.id)
            hasher.combine(transaction.amount)
            hasher.combine(transaction.isExpense)
            hasher.combine(transaction.date)
            hasher.combine(transaction.dailyBudgetOverride)
            hasher.combine(transaction.category?.id)
        }
        // 分类的展示与预算归属字段单独过一遍小表，而不是逐笔交易重复读取。
        for category in categories {
            hasher.combine(category.id)
            hasher.combine(category.name)
            hasher.combine(category.icon)
            hasher.combine(category.colorHex)
            hasher.combine(category.parentCategoryName)
            hasher.combine(category.defaultKey)
            hasher.combine(category.dailyBudgetOverride)
        }
        for budget in budgets {
            hasher.combine(budget.id)
            hasher.combine(budget.monthlyLimit)
            hasher.combine(budget.year)
            hasher.combine(budget.month)
            hasher.combine(budget.categoryId)
            hasher.combine(budget.createdAt)
        }
        return hasher.finalize()
    }

    var body: some View {
        // 一次 body 求值只算一遍摘要，任务标识与缓存键共用。
        let generationKey = GenerationKey(
            isActive: isActive,
            digest: transactionDigest,
            retry: retryToken,
            weekendBudgetMultiplierPercent: weekendBudgetMultiplierPercent,
            period: period,
            payday: payday,
            targetKind: target.isCurrent ? "current" : (target.isScheduled ? "scheduled" : "completed"),
            targetReferenceDate: target.referenceDate
        )

        return Group {
            switch state {
            case .loading:
                ProgressView("正在生成报表…")
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .accessibilityIdentifier("report.loading")
            case .failed(let message):
                ContentUnavailableView {
                    Label("报表读取失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") { retryToken += 1 }
                        .accessibilityIdentifier("report.retry")
                }
            case .empty(let data):
                VStack(spacing: DesignSystem.sectionSpacing) {
                    ContentUnavailableView(
                        "该报告期暂无记录",
                        systemImage: "chart.bar.xaxis",
                        description: Text("记录一笔收支后，这里会生成趋势与消费洞察。")
                    )
                    .accessibilityIdentifier("report.empty")
                    budgetCard(data.budget)
                }
            case .refreshing(let data):
                reportContent(data)
                    .overlay(alignment: .topTrailing) { ProgressView().controlSize(.small) }
            case .loaded(let data):
                reportContent(data)
            }
        }
        .sheet(item: $drillDown) { request in
            ReportDrillDownView(request: request)
        }
        .task(id: generationKey) {
            // 不活跃时跳过；isActive 参与 key，回到前台会重新触发并按最新数据生成。
            guard isActive else { return }
            await generateReport(digest: generationKey.digest)
        }
    }

    /// 下钻页副标题：沿用报表自己的区间文案，避免两处口径出现分歧。
    func drillDownSubtitle(for data: ReportData) -> String {
        ReportDateRangeFormatter().reportRange(data.reportRange, period: data.period).title
    }

    @ViewBuilder
    private func reportContent(_ page: ReportPageData) -> some View {
        let data = page.report
        VStack(spacing: DesignSystem.sectionSpacing) {
            streakCard(days: data.streakDays)
            summaryCard(data: data)
            smartAnalysisCard(data: data)
            budgetCard(page.budget)
            timeBucketBarChart(data: data)
            categoryPieChart(data: data)
            topCategoriesCard(data: data)
            insightsCard(data: data)
        }
    }

    /// 已完成 / 定时报表在数据不变时结果确定，可以缓存；
    /// 「当前进行中」的参照时刻持续变化，缓存键永远打不中，不参与缓存。
    private func cacheKey(digest: Int) -> ReportPageCache.Key? {
        guard !target.isCurrent else { return nil }
        return ReportPageCache.Key(
            digest: digest,
            period: period,
            targetKind: target.isScheduled ? "scheduled" : "completed",
            targetReferenceDate: target.referenceDate,
            payday: payday,
            weekendMultiplierPercent: weekendBudgetMultiplierPercent
        )
    }

    @MainActor
    private func generateReport(digest: Int) async {
        let token = UUID()
        generationToken = token
        let key = cacheKey(digest: digest)

        if let key, let cached = await ReportPageCache.shared.value(for: key) {
            guard generationToken == token else { return }
            apply(cached)
            return
        }

        let previous = state.visibleData
        state = previous.map(ReportLoadState.refreshing) ?? .loading
        do {
            let snapshotStore = LocalAnalyticsDataStore(modelContainer: modelContext.container)
            let snapshot = try await snapshotStore.makeSnapshot(
                period: period,
                target: target,
                payday: payday,
                calendar: .current
            )
            try Task.checkCancellation()
            let calculation = await ReportComputationWorker().calculatePage(
                period: period,
                target: target,
                payday: payday,
                calendar: .current,
                snapshot: snapshot,
                weekendMultiplier: weekendBudgetMultiplier
            )
            try Task.checkCancellation()
            if let key {
                await ReportPageCache.shared.insert(calculation, for: key)
            }
            guard generationToken == token else { return }
            apply(calculation)
        } catch {
            guard !Task.isCancelled, generationToken == token else { return }
            state = .failed(error.localizedDescription)
        }
    }

    @MainActor
    private func apply(_ calculation: ReportPageCalculation) {
        let page = ReportPageData(report: calculation.report, budget: calculation.budget)
        withAnimation(reduceMotion ? nil : DesignSystem.standardAnimation) {
            state = calculation.report.transactionCount == 0 ? .empty(page) : .loaded(page)
        }
    }
}
