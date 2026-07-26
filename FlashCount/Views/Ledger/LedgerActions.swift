import Foundation
import SwiftUI
import SwiftData

// MARK: - 分页加载与删除/撤销动作

extension LedgerView {
    func resetLedgerPage() {
        loadedTransactions.removeAll()
        totalTransactionCount = 0
        ledgerSummary = nil
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
        do {
            let store = LedgerQueryDataStore(modelContainer: modelContext.container)
            let page = try await store.fetchPage(filter: filter, offset: 0, limit: transactionPageSize)
            let summary = try await store.summary(filter: filter)
            try Task.checkCancellation()
            guard queryID == ledgerQueryID else { return }
            loadedTransactions = materialize(page.persistentIDs)
            totalTransactionCount = page.totalCount
            ledgerSummary = summary
        } catch {
            guard !Task.isCancelled, queryID == ledgerQueryID else { return }
            loadedTransactions = []
            totalTransactionCount = 0
            ledgerSummary = nil
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
        } catch {
            guard !Task.isCancelled, queryID == ledgerQueryID else { return }
            deleteError = error.localizedDescription
        }
    }

    func selectAllMatchingTransactions() {
        let queryID = ledgerQueryID
        let filter = currentLedgerFilter
        Task {
            do {
                let ids = try await LedgerQueryDataStore(modelContainer: modelContext.container)
                    .fetchMatchingTransactionIDs(filter: filter)
                try Task.checkCancellation()
                guard queryID == ledgerQueryID else { return }
                selectedIds = ids
            } catch is CancellationError {
                return
            } catch {
                batchDeleteError = error.localizedDescription
            }
        }
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
        undoWorkItem?.cancel()
        let task = DispatchWorkItem { [self] in
            withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                self.undoInfo = nil
            }
        }
        undoWorkItem = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: task)
    }

    func undoDelete() {
        guard let info = undoInfo else { return }
        undoWorkItem?.cancel()

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
