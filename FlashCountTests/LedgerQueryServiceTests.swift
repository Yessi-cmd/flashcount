import XCTest
import SwiftData
@testable import FlashCount

@MainActor
final class LedgerQueryServiceTests: XCTestCase {
    func testPagingUsesFixedPagesAndDeduplicatesAcrossOffsets() throws {
        let context = try makeContext()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<405 {
            context.insert(Transaction(
                amount: Decimal(index + 1),
                date: baseDate.addingTimeInterval(TimeInterval(index))
            ))
        }
        try context.save()

        let filter = makeFilter()
        let service = LedgerQueryService(modelContext: context)
        let first = try service.fetchPage(filter: filter, offset: 0, limit: 200)
        let second = try service.fetchPage(filter: filter, offset: 200, limit: 200)
        let third = try service.fetchPage(filter: filter, offset: 400, limit: 200)

        XCTAssertEqual(first.transactions.count, 200)
        XCTAssertEqual(second.transactions.count, 200)
        XCTAssertEqual(third.transactions.count, 5)
        XCTAssertEqual(first.totalCount, 405)
        XCTAssertTrue(third.hasMore == false)
        XCTAssertEqual(Set((first.transactions + second.transactions + third.transactions).map(\.id)).count, 405)
        XCTAssertEqual(first.transactions.first?.amount, Decimal(405))
        XCTAssertEqual(third.transactions.last?.amount, Decimal(1))
    }

    func testPostFilterSearchAndMatchingIDsShareTheSameResultSet() throws {
        let context = try makeContext()
        let matching = Transaction(amount: 12.50, note: "每月房租")
        let other = Transaction(amount: 12.50, note: "午餐")
        context.insert(matching)
        context.insert(other)
        try context.save()

        var filter = makeFilter()
        filter = LedgerFilter(
            startDate: nil,
            endDate: nil,
            isExpense: true,
            categoryID: nil,
            categoryRootName: nil,
            minAmount: nil,
            maxAmount: nil,
            searchText: "房租",
            includeProtectedIncomeMetadata: true,
            sortField: .date,
            sortDirection: .descending
        )

        let service = LedgerQueryService(modelContext: context)
        let page = try service.fetchPage(filter: filter, offset: 0, limit: 200)
        let ids = try service.fetchMatchingIDs(filter: filter)

        XCTAssertEqual(page.totalCount, 1)
        XCTAssertEqual(page.transactions.map(\.id), [matching.id])
        XCTAssertEqual(ids, [matching.id])
    }

    func testBackgroundStoreReturnsOnlyOnePageOfReferences() async throws {
        let context = try makeContext()
        for index in 0..<405 {
            context.insert(Transaction(amount: Decimal(index + 1)))
        }
        try context.save()

        let page = try await LedgerQueryDataStore(modelContainer: context.container)
            .fetchPage(filter: makeFilter(), offset: 0, limit: 200)

        XCTAssertEqual(page.persistentIDs.count, 200)
        XCTAssertEqual(page.transactionIDs.count, 200)
        XCTAssertEqual(page.totalCount, 405)
        XCTAssertTrue(page.hasMore)
    }

    func testSummaryRespectsPrivacyStatePassedThroughFilter() throws {
        let context = try makeContext()
        context.insert(Transaction(amount: 120, isExpense: false))
        try context.save()

        let service = LedgerQueryService(modelContext: context)
        var lockedFilter = makeFilter()
        lockedFilter = LedgerFilter(
            startDate: lockedFilter.startDate,
            endDate: lockedFilter.endDate,
            isExpense: lockedFilter.isExpense,
            categoryID: lockedFilter.categoryID,
            categoryRootName: lockedFilter.categoryRootName,
            minAmount: lockedFilter.minAmount,
            maxAmount: lockedFilter.maxAmount,
            searchText: lockedFilter.searchText,
            includeProtectedIncomeMetadata: false,
            sortField: lockedFilter.sortField,
            sortDirection: lockedFilter.sortDirection
        )
        let unlockedFilter = LedgerFilter(
            startDate: lockedFilter.startDate,
            endDate: lockedFilter.endDate,
            isExpense: lockedFilter.isExpense,
            categoryID: lockedFilter.categoryID,
            categoryRootName: lockedFilter.categoryRootName,
            minAmount: lockedFilter.minAmount,
            maxAmount: lockedFilter.maxAmount,
            searchText: lockedFilter.searchText,
            includeProtectedIncomeMetadata: true,
            sortField: lockedFilter.sortField,
            sortDirection: lockedFilter.sortDirection
        )

        XCTAssertTrue(try service.summary(filter: lockedFilter).hasHiddenIncome)
        XCTAssertFalse(try service.summary(filter: unlockedFilter).hasHiddenIncome)
    }

    private func makeFilter() -> LedgerFilter {
        LedgerFilter(
            startDate: nil,
            endDate: nil,
            isExpense: nil,
            categoryID: nil,
            categoryRootName: nil,
            minAmount: nil,
            maxAmount: nil,
            searchText: nil,
            includeProtectedIncomeMetadata: true,
            sortField: .date,
            sortDirection: .descending
        )
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Transaction.self,
            Category.self,
            Ledger.self,
            RecurringRule.self,
            Budget.self,
            Asset.self,
            PhysicalAsset.self,
            CashPoolItem.self,
            CashPoolState.self,
            SavingsGoal.self,
            InstallmentBill.self,
            TransactionTemplate.self,
            Reminder.self,
            RecurringOccurrence.self,
            configurations: configuration
        )
        return ModelContext(container)
    }
}
