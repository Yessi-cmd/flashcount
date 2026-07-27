import XCTest
import SwiftData
@testable import FlashCount

/// 可动用资金 = 资金净额 + 交易增减 − 分期待还。
/// 还款会让「分期待还」下降，若不同时记账，这个公式就会凭空多出一笔钱。
@MainActor
final class InstallmentRepaymentServiceTests: XCTestCase {
    func testRepayingAnInstallmentKeepsAvailableFundsUnchanged() throws {
        let context = try makeContext()
        context.insert(CashPoolItem(name: "现金", kind: .cash, amount: 1_000))
        let bill = makeBill(total: 600, count: 3)
        context.insert(bill)
        try context.save()

        let before = try availableAmount(in: context, bill: bill)
        XCTAssertEqual(before, 400, "1000 现金减去 600 待还")

        let transaction = try InstallmentRepaymentService(modelContext: context)
            .repayOneInstallment(bill, draft: .init(amount: 200))

        XCTAssertEqual(bill.normalizedPaidInstallments, 1)
        XCTAssertEqual(bill.remainingAmount, 400)

        let created = try XCTUnwrap(transaction, "默认应生成对应的支出交易")
        XCTAssertTrue(created.isExpense)
        XCTAssertEqual(created.amount, 200)
        XCTAssertEqual(created.note, "手机分期 第 1 期")
        XCTAssertEqual(created.cashPoolDelta, -200)

        let after = try availableAmount(in: context, bill: bill)
        XCTAssertEqual(after, before, "还债不该让可动用资金上升")
    }

    /// 关掉记账是给「已经手动记过这笔支出」的用户用的：
    /// 此时账本里已有那笔流出，只推进期数才刚好抵消。
    func testSkippingTheTransactionOnlyAdvancesTheSchedule() throws {
        let context = try makeContext()
        context.insert(CashPoolItem(name: "现金", kind: .cash, amount: 1_000))
        let bill = makeBill(total: 600, count: 3)
        context.insert(bill)
        try context.save()

        let transaction = try InstallmentRepaymentService(modelContext: context)
            .repayOneInstallment(bill, draft: .init(amount: 200, recordsTransaction: false))

        XCTAssertNil(transaction)
        XCTAssertEqual(bill.normalizedPaidInstallments, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 0)
        XCTAssertEqual(try availableAmount(in: context, bill: bill), 600, "仅推进期数时余额随负债释放而上升")
    }

    func testLastInstallmentAbsorbsRoundingSoTheBillClosesExactly() throws {
        let context = try makeContext()
        let bill = makeBill(total: 1_000, count: 3)
        context.insert(bill)
        try context.save()

        let service = InstallmentRepaymentService(modelContext: context)
        var paid: Decimal = 0
        for _ in 0..<3 {
            let amount = InstallmentRepaymentService.suggestedAmount(for: bill)
            paid += amount
            try service.repayOneInstallment(bill, draft: .init(amount: amount))
        }

        XCTAssertEqual(paid, 1_000, "三期建议金额之和必须正好等于总额")
        XCTAssertTrue(bill.isCompleted)
    }

    func testCustomRepaymentAmountIsRejectedBeforeAdvancingSchedule() throws {
        let context = try makeContext()
        context.insert(CashPoolItem(name: "现金", kind: .cash, amount: 1_000))
        let bill = makeBill(total: 600, count: 3)
        context.insert(bill)
        try context.save()

        let before = try availableAmount(in: context, bill: bill)
        XCTAssertThrowsError(
            try InstallmentRepaymentService(modelContext: context)
                .repayOneInstallment(bill, draft: .init(amount: 100))
        ) { error in
            guard case let InstallmentRepaymentService.RepaymentError.amountMismatch(expected) = error else {
                return XCTFail("应拒绝与本期应还额不一致的金额，实际错误：\(error)")
            }
            XCTAssertEqual(expected, 200)
        }

        XCTAssertEqual(bill.normalizedPaidInstallments, 0)
        XCTAssertEqual(bill.remainingAmount, 600)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 0)
        XCTAssertEqual(try availableAmount(in: context, bill: bill), before)
    }

    func testRepayingACompletedBillIsRejected() throws {
        let context = try makeContext()
        let bill = makeBill(total: 100, count: 1)
        bill.paidInstallments = 1
        context.insert(bill)
        try context.save()

        XCTAssertThrowsError(
            try InstallmentRepaymentService(modelContext: context)
                .repayOneInstallment(bill, draft: .init(amount: 100))
        )
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 0)
    }

    // MARK: - 工具

    private func makeBill(total: Decimal, count: Int) -> InstallmentBill {
        InstallmentBill(
            name: "手机分期",
            totalAmount: total,
            installmentCount: count,
            repaymentDay: 10,
            firstRepaymentDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func availableAmount(in context: ModelContext, bill: InstallmentBill) throws -> Decimal {
        let service = CashPoolService(modelContext: context)
        let items = try context.fetch(FetchDescriptor<CashPoolItem>())
        return service.availableAmount(
            items: items,
            state: try service.state(),
            installmentLiability: bill.remainingAmount
        )
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema(versionedSchema: FlashCountSchemaV3.self),
            configurations: configuration
        )
        return ModelContext(container)
    }
}
