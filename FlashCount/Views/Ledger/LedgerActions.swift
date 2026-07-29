import Foundation
import SwiftUI
import SwiftData

// MARK: - 分页加载与删除/撤销动作

extension LedgerView {
    func resetLedgerPage() {
        cancelSelectAllTask()
        loadedTransactions.removeAll()
        totalTransactionCount = 0
        ledgerSummary = nil
        ledgerPresentation = .empty
        loadedLedgerQueryID = nil
        selectedIds.removeAll()
    }

    func loadFirstPage() async {
        let requestID = UUID()
        pageLoadToken = requestID
        isLoadingPage = true
        defer {
            if pageLoadToken == requestID {
                isLoadingPage = false
            }
        }

        let queryID = ledgerQueryID
        let filter = currentLedgerFilter
        if loadedLedgerQueryID != queryID {
            loadedTransactions = []
            totalTransactionCount = 0
            ledgerSummary = nil
            ledgerPresentation = .empty
        }
        do {
            let store = LedgerQueryDataStore(modelContainer: modelContext.container)
            let snapshot = try await store.fetchPageSnapshot(
                filter: filter,
                offset: 0,
                limit: transactionPageSize
            )
            try Task.checkCancellation()
            guard queryID == ledgerQueryID else { return }
            loadedTransactions = materialize(snapshot.page.persistentIDs)
            totalTransactionCount = snapshot.page.totalCount
            ledgerSummary = snapshot.summary
            loadedLedgerQueryID = queryID
            rebuildPresentation()
        } catch {
            guard !Task.isCancelled, queryID == ledgerQueryID else { return }
            loadedTransactions = []
            totalTransactionCount = 0
            ledgerSummary = nil
            ledgerPresentation = .empty
            loadedLedgerQueryID = nil
            deleteError = error.localizedDescription
        }
    }

    func loadNextPage() async {
        guard !isLoadingPage, loadedTransactions.count < totalTransactionCount else { return }
        let offset = loadedTransactions.count
        let queryID = ledgerQueryID
        let filter = currentLedgerFilter
        let requestID = UUID()
        pageLoadToken = requestID
        isLoadingPage = true
        defer {
            if pageLoadToken == requestID {
                isLoadingPage = false
            }
        }

        do {
            let store = LedgerQueryDataStore(modelContainer: modelContext.container)
            let page = try await store.fetchPage(filter: filter, offset: offset, limit: transactionPageSize)
            try Task.checkCancellation()
            guard queryID == ledgerQueryID, loadedTransactions.count == offset else { return }
            let existingIDs = Set(loadedTransactions.map(\.id))
            loadedTransactions.append(contentsOf: materialize(page.persistentIDs).filter { !existingIDs.contains($0.id) })
            totalTransactionCount = page.totalCount
            rebuildPresentation()
        } catch {
            guard !Task.isCancelled, queryID == ledgerQueryID else { return }
            deleteError = error.localizedDescription
        }
    }

    /// 行动中心 badge 的数量。
    ///
    /// 输入刻意和 `ActionCenterView` 保持一致（同一份支出交易、同一批已忽略建议），
    /// 否则会出现 badge 说 3 项、打开却是 4 项——一个比不显示数量更糟的结果。
    /// 这里包含 `pendingOccurrences` 的推演，所以只在 digest 变化时跑一次。
    func refreshPendingActionCount() async {
        let dismissedSuggestionFingerprints = UserDefaultsRecurringSuggestionDismissalStore().load()
        do {
            let count = try await LocalActionCenterDataStore(
                modelContainer: modelContext.container
            ).totalCount(
                dismissedSuggestionFingerprints: dismissedSuggestionFingerprints,
                payday: payday,
                weekendMultiplier: WeekendBudgetPreferences.multiplier(
                    for: weekendBudgetMultiplierPercent
                )
            )
            try Task.checkCancellation()
            pendingActionCount = count
        } catch is CancellationError {
            return
        } catch {
            pendingActionCount = 0
        }
    }

    func selectAllMatchingTransactions() {
        cancelSelectAllTask()
        let queryID = ledgerQueryID
        let filter = currentLedgerFilter
        let token = UUID()
        selectAllLoadToken = token
        selectAllTask = Task { @MainActor in
            defer {
                if selectAllLoadToken == token {
                    selectAllLoadToken = nil
                    selectAllTask = nil
                }
            }
            do {
                let ids = try await LedgerQueryDataStore(modelContainer: modelContext.container)
                    .fetchMatchingTransactionIDs(filter: filter)
                try Task.checkCancellation()
                guard queryID == ledgerQueryID, selectAllLoadToken == token else { return }
                selectedIds = ids
            } catch is CancellationError {
                return
            } catch {
                batchDeleteError = error.localizedDescription
            }
        }
    }

    func cancelSelectAllTask() {
        selectAllTask?.cancel()
        selectAllTask = nil
        selectAllLoadToken = nil
    }

    func materialize(_ persistentIDs: [PersistentIdentifier]) -> [Transaction] {
        persistentIDs.compactMap { modelContext.model(for: $0) as? Transaction }
    }

    func batchDeleteSelected() {
        do {
            let toDelete = try LedgerQueryService(modelContext: modelContext)
                .fetchTransactions(ids: selectedIds)
            try TransactionMutationService(modelContext: modelContext).delete(toDelete)
            HapticManager.success()
            withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                selectedIds.removeAll()
                isSelecting = false
            }
        } catch {
            batchDeleteError = error.localizedDescription
        }
    }

    func deleteTransaction(_ transaction: Transaction) {
        let snapshot: DeletedTransactionSnapshot
        do {
            snapshot = try TransactionMutationService(modelContext: modelContext).delete(transaction)
        } catch {
            deleteError = error.localizedDescription
            return
        }

        // 显示撤销条
        withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
            undoInfo = snapshot
        }
        undoDismissTask?.cancel()
        let token = UUID()
        undoDismissToken = token
        undoDismissTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                return
            }
            guard undoDismissToken == token else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                undoInfo = nil
            }
            undoDismissTask = nil
            undoDismissToken = nil
        }
    }

    func undoDelete() {
        guard let info = undoInfo else { return }
        undoDismissTask?.cancel()
        undoDismissTask = nil
        undoDismissToken = nil

        do {
            try TransactionMutationService(modelContext: modelContext).restore(info)
        } catch {
            deleteError = error.localizedDescription
            HapticManager.error()
            return
        }

        withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
            undoInfo = nil
        }
        HapticManager.success()
    }
}
