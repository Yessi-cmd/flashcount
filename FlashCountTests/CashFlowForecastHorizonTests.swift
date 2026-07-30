import SwiftData
import XCTest
@testable import FlashCount

/// 现金流预测的时间跨度、口径与最低点。
///
/// 用户看这张图真正要问的是「哪天会不够钱」，所以起始余额、最低点和
/// 两种口径的差别都必须准确；同时预测是纯读操作，不能顺手改动任何数据。
@MainActor
final class CashFlowForecastHorizonTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - 时间跨度

    func testFixedHorizonsSpanTheExpectedNumberOfDays() throws {
        let calendar = Calendar(identifier: .gregorian)

        for (horizon, days) in [
            (CashFlowForecastHorizon.thirtyDays, 30),
            (.sixtyDays, 60),
            (.ninetyDays, 90)
        ] {
            let forecast = makeForecast(horizon: horizon, calendar: calendar)
            let span = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: reference),
                to: forecast.endDate
            ).day
            XCTAssertEqual(span, days, "\(horizon.rawValue) 应覆盖 \(days) 天")
            XCTAssertEqual(forecast.horizon, horizon)
        }
    }

    /// 「本周期」跟着发薪日走，而不是固定天数——这是它与 30 天档的根本区别。
    func testCurrentCycleHorizonFollowsThePayday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

        let forecast = makeForecast(horizon: .currentCycle, payday: 15, calendar: calendar)
        let expected = PayCycleService.cycle(containing: reference, payday: 15, calendar: calendar).end

        XCTAssertEqual(forecast.endDate, expected)

        let otherPayday = makeForecast(horizon: .currentCycle, payday: 1, calendar: calendar)
        XCTAssertNotEqual(otherPayday.endDate, forecast.endDate, "换发薪日应改变本周期的终点")
    }

    // MARK: - 起始余额

    /// 起始余额 = 资金项合计 + 记账增减，且归档的资金项不参与。
    func testOpeningBalanceCombinesActiveItemsAndLedgerDelta() throws {
        let cash = CashPoolItem(name: "现金", kind: .cash, amount: 1_000, sortOrder: 0)
        let liability = CashPoolItem(name: "信用卡待还", kind: .liability, amount: 300, sortOrder: 1)
        let archived = CashPoolItem(name: "旧账户", kind: .cash, amount: 9_999, sortOrder: 2)
        archived.isArchived = true

        let forecast = CashFlowForecastService.forecast(
            cashPoolItems: [cash, liability, archived],
            cashPoolState: CashPoolState(transactionDelta: -200),
            recurringRules: [],
            occurrences: [],
            installmentBills: [],
            transactions: [],
            referenceDate: reference,
            horizon: .thirtyDays,
            mode: .fixedOnly,
            calendar: Calendar(identifier: .gregorian)
        )

        XCTAssertEqual(forecast.openingBalance, 500, "1000 − 300 − 200；归档项不计入")
        XCTAssertEqual(forecast.endingBalance, 500, "没有任何事项时结余等于起始余额")
        XCTAssertEqual(forecast.netChange, 0)
    }

    // MARK: - 两种口径

    /// `fixedOnly` 不含日常消费估算，`fixedAndRoutine` 含——后者的预计支出必须更高。
    ///
    /// 日均估算只统计「计入日常预算」的支出（`BudgetScope`），这里用单笔
    /// `dailyBudgetOverride` 显式声明，避免依赖默认分类种子。
    func testRoutineModeAddsEstimatedSpendingOnTopOfFixedItems() throws {
        let calendar = Calendar(identifier: .gregorian)
        let history = (1...30).map { day -> Transaction in
            let transaction = Transaction(
                amount: 30,
                isExpense: true,
                note: "日常\(day)",
                date: calendar.date(byAdding: .day, value: -day, to: reference) ?? reference
            )
            transaction.dailyBudgetOverride = true
            return transaction
        }

        let fixedOnly = makeForecast(mode: .fixedOnly, transactions: history, calendar: calendar)
        let withRoutine = makeForecast(mode: .fixedAndRoutine, transactions: history, calendar: calendar)

        XCTAssertEqual(fixedOnly.estimatedExpense, 0, "固定口径不该带入日常估算")
        XCTAssertEqual(fixedOnly.dailyRoutineExpense, 0)
        XCTAssertGreaterThan(withRoutine.dailyRoutineExpense, 0, "有历史消费时应估出日均值")
        XCTAssertGreaterThan(withRoutine.estimatedExpense, fixedOnly.estimatedExpense)
        XCTAssertLessThan(withRoutine.endingBalance, fixedOnly.endingBalance, "带日常估算的结余应更低")
    }

    /// 不计入日常预算的支出（大件、固定账单等）不该抬高日均估算——
    /// 否则买一次电脑会让接下来 90 天的预测都失真。
    func testSpendingOutsideDailyBudgetScopeDoesNotInflateTheEstimate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let bigPurchase = Transaction(
            amount: 12_000,
            isExpense: true,
            note: "买电脑",
            date: calendar.date(byAdding: .day, value: -3, to: reference) ?? reference
        )
        bigPurchase.dailyBudgetOverride = false

        let forecast = makeForecast(mode: .fixedAndRoutine, transactions: [bigPurchase], calendar: calendar)

        XCTAssertEqual(forecast.dailyRoutineExpense, 0)
        XCTAssertEqual(forecast.estimatedExpense, 0)
    }

    func testWithoutHistoryThereIsNoRoutineEstimate() throws {
        let forecast = makeForecast(mode: .fixedAndRoutine, transactions: [], calendar: Calendar(identifier: .gregorian))
        XCTAssertEqual(forecast.dailyRoutineExpense, 0, "没有历史消费就不该凭空估算")
        XCTAssertEqual(forecast.estimatedExpense, 0)
        XCTAssertNil(forecast.routineProfile)
        XCTAssertFalse(forecast.hasBalanceRange)
    }

    func testRoutineRangeOrdersBalancesAndKeepsEstimatesOutOfKnownEvents() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let referenceDay = calendar.startOfDay(for: reference)
        let weeklyTotals = [70, 140, 210, 280, 350, 420, 490, 560]
        let history = try weeklyTotals.enumerated().map { index, total -> Transaction in
            let weekStart = try XCTUnwrap(
                calendar.date(
                    byAdding: .day,
                    value: -((index + 1) * 7),
                    to: referenceDay
                )
            )
            let transaction = Transaction(
                amount: Decimal(total),
                date: try XCTUnwrap(
                    calendar.date(byAdding: .day, value: 2, to: weekStart)
                )
            )
            transaction.dailyBudgetOverride = true
            return transaction
        }
        let fixedDate = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 5, to: reference)
        )
        let fixedRule = RecurringRule(
            title: "房租",
            amount: 100,
            frequency: .monthly,
            nextDueDate: fixedDate
        )

        let forecast = CashFlowForecastService.forecast(
            cashPoolItems: [
                CashPoolItem(name: "现金", kind: .cash, amount: 5_000)
            ],
            cashPoolState: nil,
            recurringRules: [fixedRule],
            occurrences: [],
            installmentBills: [],
            transactions: history,
            referenceDate: reference,
            horizon: .thirtyDays,
            mode: .fixedAndRoutine,
            calendar: calendar
        )

        XCTAssertEqual(forecast.routineProfile?.dataBasis, .sufficient)
        XCTAssertTrue(forecast.hasBalanceRange)
        XCTAssertEqual(forecast.events.count, 1, "事件列表只应保留真正的固定事项")
        XCTAssertFalse(forecast.events.contains { $0.source == .routine })
        XCTAssertLessThan(
            forecast.lighterEstimatedExpense,
            forecast.estimatedExpense
        )
        XCTAssertLessThan(
            forecast.estimatedExpense,
            forecast.higherEstimatedExpense
        )
        XCTAssertTrue(
            forecast.points.allSatisfy {
                $0.lowerBalance <= $0.typicalBalance
                    && $0.typicalBalance <= $0.upperBalance
            }
        )
        XCTAssertLessThan(
            forecast.endingBalanceLowerBound,
            forecast.endingBalance
        )
        XCTAssertLessThan(
            forecast.endingBalance,
            forecast.endingBalanceUpperBound
        )
        XCTAssertEqual(
            forecast.points.first { !$0.events.isEmpty }?.confirmedOutflow,
            100
        )
    }

    func testRoutineEstimateMultipliesBeforeDividingWeeklyAmount() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let currentWeekStart = try XCTUnwrap(
            calendar.dateInterval(of: .weekOfYear, for: reference)?.start
        )
        let previousWeekStart = try XCTUnwrap(
            calendar.date(
                byAdding: .weekOfYear,
                value: -1,
                to: currentWeekStart
            )
        )
        let transaction = Transaction(
            amount: 100,
            date: try XCTUnwrap(
                calendar.date(byAdding: .day, value: 2, to: previousWeekStart)
            ),
            dailyBudgetOverride: true
        )

        let forecast = makeForecast(
            mode: .fixedAndRoutine,
            transactions: [transaction],
            calendar: calendar
        )
        let estimatedDays = Decimal(forecast.points.count - 1)
        let expectedExpense = Decimal(100) * estimatedDays / Decimal(7)

        XCTAssertEqual(forecast.estimatedExpense, expectedExpense)
        XCTAssertEqual(
            forecast.endingBalance,
            forecast.openingBalance - expectedExpense
        )
    }

    // MARK: - 最低点

    /// 最低点要指向真正最低的那一天，而不是最后一天——「哪天会不够」是这张图的核心问题。
    func testLowestPointIsTheDayBalanceBottomsOut() throws {
        let calendar = Calendar(identifier: .gregorian)
        let bigBillDate = calendar.date(byAdding: .day, value: 5, to: reference) ?? reference
        let salaryDate = calendar.date(byAdding: .day, value: 20, to: reference) ?? reference

        let rent = RecurringRule(
            title: "房租",
            amount: 800,
            isExpense: true,
            frequency: .monthly,
            nextDueDate: bigBillDate
        )
        let salary = RecurringRule(
            title: "工资",
            amount: 5_000,
            isExpense: false,
            frequency: .monthly,
            nextDueDate: salaryDate
        )

        let forecast = CashFlowForecastService.forecast(
            cashPoolItems: [CashPoolItem(name: "现金", kind: .cash, amount: 1_000, sortOrder: 0)],
            cashPoolState: nil,
            recurringRules: [rent, salary],
            occurrences: [],
            installmentBills: [],
            transactions: [],
            referenceDate: reference,
            horizon: .thirtyDays,
            mode: .fixedOnly,
            calendar: calendar
        )

        let lowest = try XCTUnwrap(forecast.lowestPoint)
        XCTAssertEqual(lowest.closingBalance, 200, "房租扣掉后是 1000 − 800")
        XCTAssertLessThan(lowest.closingBalance, forecast.endingBalance, "发薪之后余额回升，最低点不应是最后一天")
        XCTAssertEqual(forecast.confirmedIncome, 5_000)
        XCTAssertEqual(forecast.confirmedExpense, 800)
    }

    func testFirstNegativeDateIsDistinctFromLowestBalanceDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let firstDebitDate = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 3, to: reference)
        )
        let secondDebitDate = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 5, to: reference)
        )
        let recoveryDate = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 10, to: reference)
        )
        let rules = [
            RecurringRule(
                title: "第一次扣款",
                amount: 120,
                frequency: .monthly,
                nextDueDate: firstDebitDate
            ),
            RecurringRule(
                title: "第二次扣款",
                amount: 50,
                frequency: .monthly,
                nextDueDate: secondDebitDate
            ),
            RecurringRule(
                title: "收入",
                amount: 500,
                isExpense: false,
                frequency: .monthly,
                nextDueDate: recoveryDate
            ),
        ]

        let forecast = CashFlowForecastService.forecast(
            cashPoolItems: [
                CashPoolItem(name: "现金", kind: .cash, amount: 100)
            ],
            cashPoolState: nil,
            recurringRules: rules,
            occurrences: [],
            installmentBills: [],
            transactions: [],
            referenceDate: reference,
            horizon: .thirtyDays,
            mode: .fixedOnly,
            calendar: calendar
        )

        let firstNegative = try XCTUnwrap(
            forecast.firstNegativePoint(for: .typical)
        )
        let lowest = try XCTUnwrap(
            forecast.lowestPoint(for: .typical)
        )
        XCTAssertEqual(
            firstNegative.date,
            calendar.startOfDay(for: firstDebitDate)
        )
        XCTAssertEqual(
            lowest.date,
            calendar.startOfDay(for: secondDebitDate)
        )
        XCTAssertEqual(firstNegative.balance(for: .typical), -20)
        XCTAssertEqual(lowest.balance(for: .typical), -70)
    }

    /// 停用的周期规则不该出现在预测里。
    func testInactiveRulesAreIgnored() throws {
        let calendar = Calendar(identifier: .gregorian)
        let rule = RecurringRule(
            title: "已停用订阅",
            amount: 100,
            isExpense: true,
            frequency: .monthly,
            nextDueDate: calendar.date(byAdding: .day, value: 3, to: reference) ?? reference
        )
        rule.isActive = false

        let forecast = CashFlowForecastService.forecast(
            cashPoolItems: [CashPoolItem(name: "现金", kind: .cash, amount: 500, sortOrder: 0)],
            cashPoolState: nil,
            recurringRules: [rule],
            occurrences: [],
            installmentBills: [],
            transactions: [],
            referenceDate: reference,
            horizon: .thirtyDays,
            mode: .fixedOnly,
            calendar: calendar
        )

        XCTAssertTrue(forecast.events.filter { $0.source == .recurring }.isEmpty)
        XCTAssertEqual(forecast.endingBalance, 500)
    }

    // MARK: - 夹具

    private func makeForecast(
        horizon: CashFlowForecastHorizon = .thirtyDays,
        mode: CashFlowForecastMode = .fixedOnly,
        transactions: [Transaction] = [],
        payday: Int = 1,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> CashFlowForecast {
        CashFlowForecastService.forecast(
            cashPoolItems: [CashPoolItem(name: "现金", kind: .cash, amount: 2_000, sortOrder: 0)],
            cashPoolState: nil,
            recurringRules: [],
            occurrences: [],
            installmentBills: [],
            transactions: transactions,
            referenceDate: reference,
            horizon: horizon,
            mode: mode,
            payday: payday,
            calendar: calendar
        )
    }
}
