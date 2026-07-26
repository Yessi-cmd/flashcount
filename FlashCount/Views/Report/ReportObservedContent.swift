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

    let scope: ReportObservationScope
    let period: ReportPeriod
    let target: ReportTarget
    let payday: Int
    let weekendBudgetMultiplierPercent: Int

    @State private var state: ReportLoadState = .loading
    @State private var retryToken = 0
    @State var selectedBucketID: Date?
    @State var showChartDetails = false
    @State private var generationToken: UUID?

    init(
        scope: ReportObservationScope,
        period: ReportPeriod,
        target: ReportTarget,
        payday: Int,
        weekendBudgetMultiplierPercent: Int
    ) {
        self.scope = scope
        self.period = period
        self.target = target
        self.payday = payday
        self.weekendBudgetMultiplierPercent = weekendBudgetMultiplierPercent
        let start = scope.start
        let end = scope.end
        _observedTransactions = Query(
            filter: #Predicate<Transaction> { transaction in
                transaction.date >= start && transaction.date < end
            },
            sort: \Transaction.date,
            order: .reverse
        )
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
            hasher.combine(transaction.category?.reportDisplayName)
            hasher.combine(transaction.category?.reportIcon)
            hasher.combine(transaction.category?.reportColorHex)
            hasher.combine(transaction.category?.dailyBudgetOverride)
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
        Group {
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
        .task(id: GenerationKey(
            digest: transactionDigest,
            retry: retryToken,
            weekendBudgetMultiplierPercent: weekendBudgetMultiplierPercent,
            period: period,
            payday: payday,
            targetKind: target.isCurrent ? "current" : (target.isScheduled ? "scheduled" : "completed"),
            targetReferenceDate: target.referenceDate
        )) {
            await generateReport()
        }
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

    @MainActor
    private func generateReport() async {
        let token = UUID()
        generationToken = token
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
            guard generationToken == token else { return }
            let page = ReportPageData(report: calculation.report, budget: calculation.budget)
            withAnimation(reduceMotion ? nil : DesignSystem.standardAnimation) {
                state = calculation.report.transactionCount == 0 ? .empty(page) : .loaded(page)
            }
        } catch {
            guard !Task.isCancelled, generationToken == token else { return }
            state = .failed(error.localizedDescription)
        }
    }
}
