import SwiftUI
import SwiftData

/// 报表下钻请求：从「餐饮占 40%」走到「到底是哪几笔」。
struct ReportDrillDownRequest: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let range: ReportDateRange
    /// 报表按根分类聚合（`Category.reportDisplayName` 即 `rootCategoryName`），
    /// 所以下钻也按根分类过滤，口径与卡片上的数字一致。nil 表示该区间全部支出。
    let categoryRootName: String?

    static func == (lhs: ReportDrillDownRequest, rhs: ReportDrillDownRequest) -> Bool {
        lhs.id == rhs.id
    }
}

/// 下钻明细页。只查支出，与报表分类构成的口径保持一致。
struct ReportDrillDownView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var privacyLock: PrivacyLockService

    let request: ReportDrillDownRequest

    @State private var transactions: [Transaction] = []
    @State private var totalCount = 0
    @State private var totalAmount: Decimal = 0
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var editingTransaction: Transaction?

    private static let pageLimit = 200

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()

                if isLoading {
                    ProgressView("正在读取明细…")
                        .foregroundStyle(DesignSystem.textSecondary)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("明细读取失败", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadError)
                    }
                } else if transactions.isEmpty {
                    ContentUnavailableView(
                        "这一段没有支出记录",
                        systemImage: "tray",
                        description: Text("报表里的数字来自其它区间或分类。")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            summaryHeader

                            ForEach(transactions, id: \.id) { transaction in
                                Button {
                                    editingTransaction = transaction
                                } label: {
                                    TransactionRow(
                                        transaction: transaction,
                                        revealsPrivateIncome: privacyLock.isUnlocked,
                                        hidesIncome: privacyLock.hidesSensitiveAmounts
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("双击打开编辑")
                            }

                            if totalCount > transactions.count {
                                Text("仅显示最近 \(transactions.count) 笔，共 \(totalCount) 笔")
                                    .font(.caption)
                                    .foregroundStyle(DesignSystem.textTertiary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, DesignSystem.space12)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                        .accessibilityIdentifier("report.drillDown.close")
                }
            }
            .sheet(item: $editingTransaction) { transaction in
                EditTransactionView(transaction: transaction)
            }
            .task { await load() }
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(request.subtitle)
                .font(.caption)
                .foregroundStyle(DesignSystem.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(totalAmount.formattedCurrency)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(DesignSystem.textPrimary)
                Text("\(totalCount) 笔")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DesignSystem.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(DesignSystem.softFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
        .padding(.bottom, DesignSystem.space8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("report.drillDown.summary")
    }

    private func load() async {
        isLoading = true
        defer {
            if !Task.isCancelled {
                isLoading = false
            }
        }
        let filter = LedgerFilter(
            startDate: request.range.start,
            endDate: request.range.end,
            isExpense: true,
            categoryID: nil,
            categoryRootName: request.categoryRootName,
            minAmount: nil,
            maxAmount: nil,
            searchText: nil,
            includeProtectedIncomeMetadata: privacyLock.isUnlocked,
            sortField: .date,
            sortDirection: .descending
        )

        do {
            let snapshot = try await LedgerQueryDataStore(
                modelContainer: modelContext.container
            ).fetchPageSnapshot(
                filter: filter,
                offset: 0,
                limit: Self.pageLimit
            )
            try Task.checkCancellation()
            transactions = snapshot.page.persistentIDs.compactMap {
                modelContext.model(for: $0) as? Transaction
            }
            totalCount = snapshot.page.totalCount
            totalAmount = snapshot.summary.expense
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            transactions = []
            totalCount = 0
            totalAmount = 0
            loadError = error.localizedDescription
        }
    }
}
