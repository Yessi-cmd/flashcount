import XCTest
@testable import FlashCount

@MainActor
final class LocalActionCenterServiceTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testOnlyDangerBudgetCreatesBudgetAction() throws {
        let referenceDate = try date(2026, 7, 25, 12)
        let category = expenseCategory()
        let cycle = PayCycleService.cycle(containing: referenceDate, payday: 1, calendar: Calendar.current)
        let budget = Budget(
            monthlyLimit: 100,
            year: cycle.budgetYear,
            month: cycle.budgetMonth
        )

        let warningTransaction = Transaction(amount: 75, date: referenceDate, category: category)
        let warningSnapshot = LocalActionCenterService.snapshot(
            budgets: [budget],
            transactions: [warningTransaction],
            recurringRules: [],
            occurrences: [],
            pendingBackfill: [],
            installmentBills: [],
            reminders: [],
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertFalse(warningSnapshot.sections.contains { $0.kind == .budgetOverrun })

        let dangerTransaction = Transaction(amount: 150, date: referenceDate, category: category)
        let dangerSnapshot = LocalActionCenterService.snapshot(
            budgets: [budget],
            transactions: [dangerTransaction],
            recurringRules: [],
            occurrences: [],
            pendingBackfill: [],
            installmentBills: [],
            reminders: [],
            referenceDate: referenceDate,
            calendar: calendar
        )

        let item = try XCTUnwrap(dangerSnapshot.sections.first { $0.kind == .budgetOverrun }?.items.first)
        XCTAssertEqual(item.destination, .budget)
        XCTAssertEqual(item.id, "budget.overrun")
        XCTAssertEqual(item.amount, 50)
        XCTAssertTrue(item.detail.contains("已超出"))
        XCTAssertFalse(item.detail.contains("预计超支"))

        let projectedTransaction = Transaction(amount: 90, date: referenceDate, category: category)
        let projectedSnapshot = LocalActionCenterService.snapshot(
            budgets: [budget],
            transactions: [projectedTransaction],
            recurringRules: [],
            occurrences: [],
            pendingBackfill: [],
            installmentBills: [],
            reminders: [],
            referenceDate: referenceDate,
            calendar: calendar
        )
        let projectedItem = try XCTUnwrap(
            projectedSnapshot.sections.first { $0.kind == .budgetOverrun }?.items.first
        )
        let projectedReminder = try XCTUnwrap(
            BudgetReminderService.reminder(
                budgets: [budget],
                transactions: [projectedTransaction],
                ledger: nil,
                referenceDate: referenceDate,
                payday: 1,
                weekendMultiplier: 1
            )
        )
        XCTAssertEqual(projectedItem.amount, projectedReminder.analysis.projectedOverAmount)
        XCTAssertTrue(projectedItem.detail.contains("预计超支"))
    }

    func testUpcomingRecurringEventsExcludeRemoteDatesAndResolvedOccurrences() throws {
        let referenceDate = try date(2026, 7, 25, 12)
        let upcoming = RecurringRule(
            title: "会员",
            amount: 30,
            frequency: .monthly,
            nextDueDate: try date(2026, 8, 1)
        )
        let remote = RecurringRule(
            title: "远期服务",
            amount: 40,
            frequency: .monthly,
            nextDueDate: try date(2026, 10, 1)
        )
        let resolved = RecurringRule(
            title: "已处理会员",
            amount: 50,
            frequency: .monthly,
            nextDueDate: try date(2026, 8, 2)
        )
        let resolvedOccurrence = RecurringOccurrence(
            occurrenceKey: RecurringOccurrence.key(
                ruleID: resolved.id,
                scheduledDate: resolved.nextDueDate,
                calendar: calendar
            ),
            ruleID: resolved.id,
            scheduledDate: resolved.nextDueDate,
            amount: resolved.amount,
            isExpense: true,
            title: resolved.title,
            status: .generated
        )

        let snapshot = LocalActionCenterService.snapshot(
            budgets: [],
            transactions: [],
            recurringRules: [upcoming, remote, resolved],
            occurrences: [resolvedOccurrence],
            pendingBackfill: [],
            installmentBills: [],
            reminders: [],
            referenceDate: referenceDate,
            calendar: calendar
        )

        let items = try XCTUnwrap(snapshot.sections.first { $0.kind == .recurringDebit }?.items)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "会员")
        XCTAssertEqual(items.first?.amount, 30)
    }

    func testPendingRecurringAndInstallmentUseActionableDatesAndExactPaymentAmount() throws {
        let referenceDate = try date(2026, 7, 25, 12)
        let pending = RecurringOccurrencePreview(
            id: "pending-occurrence",
            ruleID: UUID(),
            scheduledDate: try date(2026, 7, 20),
            amount: 18,
            isExpense: true,
            title: "待补会员",
            note: "",
            categoryID: nil,
            ledgerID: nil,
            isProtectedIncome: false
        )
        let bill = InstallmentBill(
            name: "设备分期",
            totalAmount: 100,
            installmentCount: 3,
            paidInstallments: 2,
            repaymentDay: 1,
            firstRepaymentDate: try date(2026, 5, 1)
        )
        let expectedPayment = bill.paymentAmount(forInstallment: bill.normalizedPaidInstallments)
        let originalPaidInstallments = bill.paidInstallments

        let snapshot = LocalActionCenterService.snapshot(
            budgets: [],
            transactions: [],
            recurringRules: [],
            occurrences: [],
            pendingBackfill: [pending],
            installmentBills: [bill],
            reminders: [],
            referenceDate: referenceDate,
            calendar: calendar
        )

        let recurringItem = try XCTUnwrap(snapshot.sections.first { $0.kind == .recurringDebit }?.items.first)
        XCTAssertEqual(recurringItem.severity, .overdue)
        XCTAssertEqual(recurringItem.destination, .recurringRules)

        let installmentItem = try XCTUnwrap(snapshot.sections.first { $0.kind == .installmentDue }?.items.first)
        XCTAssertEqual(installmentItem.severity, .overdue)
        XCTAssertEqual(installmentItem.amount, expectedPayment)
        XCTAssertTrue(installmentItem.isPrivacySensitiveAmount)
        XCTAssertEqual(bill.paidInstallments, originalPaidInstallments)
    }

    func testSuggestionsAndRemindersRespectDismissalCompletionAndSectionOrder() throws {
        let referenceDate = try date(2026, 3, 11, 12)
        let category = expenseCategory()
        let suggestionTransactions = [
            Transaction(amount: 30, note: "视频会员", date: try date(2026, 1, 10), category: category),
            Transaction(amount: 30, note: "视频会员", date: try date(2026, 2, 10), category: category),
            Transaction(amount: 30, note: "视频会员", date: try date(2026, 3, 10), category: category),
        ]
        let pendingReminder = ReminderItem(
            title: "补交材料",
            dueDate: try date(2026, 3, 5)
        )
        let todayReminder = ReminderItem(
            title: "今日处理",
            dueDate: referenceDate
        )
        let futureReminder = ReminderItem(
            title: "预约体检",
            dueDate: try date(2026, 3, 15)
        )
        let completedReminder = ReminderItem(
            title: "已完成",
            dueDate: try date(2026, 3, 1),
            isCompleted: true,
            completedAt: try date(2026, 3, 2)
        )

        let snapshot = LocalActionCenterService.snapshot(
            budgets: [],
            transactions: suggestionTransactions,
            recurringRules: [],
            occurrences: [],
            pendingBackfill: [],
            installmentBills: [],
            reminders: [pendingReminder, todayReminder, futureReminder, completedReminder],
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.sections.map(\.kind), [.recurringSuggestion, .incompleteReminder])
        let suggestion = try XCTUnwrap(snapshot.sections.first { $0.kind == .recurringSuggestion }?.items.first)
        XCTAssertEqual(suggestion.title, "视频会员")
        XCTAssertEqual(suggestion.destination, .recurringRules)

        let reminders = try XCTUnwrap(snapshot.sections.first { $0.kind == .incompleteReminder }?.items)
        XCTAssertEqual(reminders.map(\.title), ["补交材料", "今日处理", "预约体检"])

        let fingerprint = try XCTUnwrap(
            RecurringSuggestionService.suggestions(
                transactions: suggestionTransactions,
                existingRules: [],
                referenceDate: referenceDate,
                calendar: calendar
            ).first?.fingerprint
        )
        let dismissed = LocalActionCenterService.snapshot(
            budgets: [],
            transactions: suggestionTransactions,
            recurringRules: [],
            occurrences: [],
            pendingBackfill: [],
            installmentBills: [],
            reminders: [],
            dismissedSuggestionFingerprints: [fingerprint],
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertFalse(dismissed.sections.contains { $0.kind == .recurringSuggestion })
    }

    func testCompletedAndArchivedBillsDoNotCreateActionsAndEmptySnapshotIsStable() throws {
        let referenceDate = try date(2026, 7, 25, 12)
        let completed = InstallmentBill(
            name: "已还清",
            totalAmount: 100,
            installmentCount: 1,
            paidInstallments: 1,
            repaymentDay: 1,
            firstRepaymentDate: try date(2026, 7, 1)
        )
        let archived = InstallmentBill(
            name: "已归档",
            totalAmount: 100,
            installmentCount: 1,
            repaymentDay: 1,
            firstRepaymentDate: try date(2026, 7, 1)
        )
        archived.isArchived = true

        let snapshot = LocalActionCenterService.snapshot(
            budgets: [],
            transactions: [],
            recurringRules: [],
            occurrences: [],
            pendingBackfill: [],
            installmentBills: [completed, archived],
            reminders: [],
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertTrue(snapshot.isEmpty)
        XCTAssertEqual(snapshot.totalCount, 0)
    }

    private func expenseCategory() -> FlashCount.Category {
        FlashCount.Category(
            name: "餐饮",
            icon: "fork.knife",
            colorHex: "#FF7A70",
            defaultKey: Category.defaultKey(for: "餐饮", isExpense: true)
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }
}
