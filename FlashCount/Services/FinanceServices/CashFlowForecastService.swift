import Foundation

/// 现金流预测的时间跨度选项。
enum CashFlowForecastHorizon: String, CaseIterable, Identifiable {
    case currentCycle
    case thirtyDays
    case sixtyDays
    case ninetyDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentCycle: return "本周期"
        case .thirtyDays: return "30 天"
        case .sixtyDays: return "60 天"
        case .ninetyDays: return "90 天"
        }
    }
}

/// 预测口径：只算已确定的固定支出，还是把日常消费的估算也计入。
enum CashFlowForecastMode: String, CaseIterable, Identifiable {
    case fixedOnly
    case fixedAndRoutine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fixedOnly: return "固定事项"
        case .fixedAndRoutine: return "固定 + 日常趋势"
        }
    }
}

/// 预测事件的来源（周期规则、分期还款等），用于在时间线上说明这笔钱从哪来。
enum CashFlowEventSource: String, Codable, CaseIterable {
    case recurring
    case installment
    case routine

    var title: String {
        switch self {
        case .recurring: return "周期账单"
        case .installment: return "分期还款"
        case .routine: return "日常消费估算"
        }
    }
}

/// 预测时间线上的一笔已知收支。
struct CashFlowEvent: Identifiable, Equatable {
    let id: String
    let date: Date
    let title: String
    let signedAmount: Decimal
    let source: CashFlowEventSource
    let isEstimated: Bool
    let isProtectedIncome: Bool

    var isExpense: Bool { signedAmount < 0 }
}

/// 预测曲线上的一天：当天余额与当天发生的事件。
struct CashFlowForecastPoint: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let openingBalance: Decimal
    let inflow: Decimal
    let outflow: Decimal
    let estimatedOutflow: Decimal
    let closingBalance: Decimal
    let events: [CashFlowEvent]
}

/// 一次现金流预测的完整结果，含最低点——用户真正要问的是「哪天会不够」。
struct CashFlowForecast: Equatable {
    let referenceDate: Date
    let endDate: Date
    let horizon: CashFlowForecastHorizon
    let mode: CashFlowForecastMode
    let openingBalance: Decimal
    let dailyRoutineExpense: Decimal
    let events: [CashFlowEvent]
    let points: [CashFlowForecastPoint]
    let confirmedIncome: Decimal
    let confirmedExpense: Decimal
    let estimatedExpense: Decimal

    var endingBalance: Decimal {
        points.last?.closingBalance ?? openingBalance
    }

    var netChange: Decimal {
        endingBalance - openingBalance
    }

    var lowestPoint: CashFlowForecastPoint? {
        points.min { $0.closingBalance < $1.closingBalance }
    }
}

/// 纯本地现金流预测器。
///
/// 预测只读取模型快照，不插入交易、不推进周期游标，也不修改资金池。
enum CashFlowForecastService {
    static func forecast(
        cashPoolItems: [CashPoolItem],
        cashPoolState: CashPoolState?,
        recurringRules: [RecurringRule],
        occurrences: [RecurringOccurrence],
        installmentBills: [InstallmentBill],
        transactions: [Transaction],
        referenceDate: Date = .now,
        horizon: CashFlowForecastHorizon = .thirtyDays,
        mode: CashFlowForecastMode = .fixedAndRoutine,
        payday: Int = 1,
        calendar: Calendar = .current,
        routineLookbackDays: Int = 90
    ) -> CashFlowForecast {
        let reference = referenceDate
        let start = calendar.startOfDay(for: reference)
        let end = endDate(
            for: horizon,
            referenceDate: reference,
            payday: payday,
            calendar: calendar
        )
        let activeItems = cashPoolItems.filter { !$0.isArchived }
        let activeBills = installmentBills.filter { !$0.isArchived }
        let openingBalance = activeItems.reduce(Decimal.zero) { $0 + $1.signedAmount }
            + (cashPoolState?.transactionDelta ?? 0)

        let resolvedOccurrenceKeys = Set(
            occurrences.compactMap { $0.status.isResolved ? $0.occurrenceKey : nil }
        )
        var events = recurringEvents(
            rules: recurringRules,
            resolvedOccurrenceKeys: resolvedOccurrenceKeys,
            referenceDate: reference,
            start: start,
            end: end,
            calendar: calendar
        )
        events.append(contentsOf: installmentEvents(
            bills: activeBills,
            referenceDate: reference,
            start: start,
            end: end,
            calendar: calendar
        ))

        let dailyRoutineExpense: Decimal
        if mode == .fixedAndRoutine {
            dailyRoutineExpense = routineExpensePerDay(
                transactions: transactions,
                referenceDate: reference,
                calendar: calendar,
                lookbackDays: routineLookbackDays
            )
        } else {
            dailyRoutineExpense = 0
        }

        if dailyRoutineExpense > 0 {
            var cursor = calendar.date(byAdding: .day, value: 1, to: start) ?? end
            while cursor < end {
                let id = "routine|\(cursor.timeIntervalSinceReferenceDate)"
                events.append(
                    CashFlowEvent(
                        id: id,
                        date: cursor,
                        title: "日常消费估算",
                        signedAmount: -dailyRoutineExpense,
                        source: .routine,
                        isEstimated: true,
                        isProtectedIncome: false
                    )
                )
                let next = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end
                guard next > cursor else { break }
                cursor = next
            }
        }

        events.sort {
            if $0.date == $1.date { return $0.id < $1.id }
            return $0.date < $1.date
        }

        let groupedEvents = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.date)
        }
        var points: [CashFlowForecastPoint] = []
        var balance = openingBalance
        var cursor = start

        while cursor < end {
            let next = min(
                calendar.date(byAdding: .day, value: 1, to: cursor) ?? end,
                end
            )
            let dayEvents = (groupedEvents[cursor] ?? []).sorted { $0.date < $1.date }
            let inflow = dayEvents.reduce(Decimal.zero) { total, event in
                total + max(event.signedAmount, 0)
            }
            let outflow = dayEvents.reduce(Decimal.zero) { total, event in
                total + max(-event.signedAmount, 0)
            }
            let estimatedOutflow = dayEvents.reduce(Decimal.zero) { total, event in
                guard event.isEstimated else { return total }
                return total + max(-event.signedAmount, 0)
            }
            let opening = balance
            balance += inflow - outflow
            points.append(
                CashFlowForecastPoint(
                    date: cursor,
                    openingBalance: opening,
                    inflow: inflow,
                    outflow: outflow,
                    estimatedOutflow: estimatedOutflow,
                    closingBalance: balance,
                    events: dayEvents
                )
            )
            guard next > cursor else { break }
            cursor = next
        }

        let confirmedIncome = events.reduce(Decimal.zero) { total, event in
            guard !event.isEstimated else { return total }
            return total + max(event.signedAmount, 0)
        }
        let confirmedExpense = events.reduce(Decimal.zero) { total, event in
            guard !event.isEstimated else { return total }
            return total + max(-event.signedAmount, 0)
        }
        let estimatedExpense = events.reduce(Decimal.zero) { total, event in
            guard event.isEstimated else { return total }
            return total + max(-event.signedAmount, 0)
        }

        return CashFlowForecast(
            referenceDate: reference,
            endDate: end,
            horizon: horizon,
            mode: mode,
            openingBalance: openingBalance,
            dailyRoutineExpense: dailyRoutineExpense,
            events: events,
            points: points,
            confirmedIncome: confirmedIncome,
            confirmedExpense: confirmedExpense,
            estimatedExpense: estimatedExpense
        )
    }

    private static func endDate(
        for horizon: CashFlowForecastHorizon,
        referenceDate: Date,
        payday: Int,
        calendar: Calendar
    ) -> Date {
        switch horizon {
        case .currentCycle:
            return PayCycleService.cycle(
                containing: referenceDate,
                payday: payday,
                calendar: calendar
            ).end
        case .thirtyDays:
            return calendar.date(byAdding: .day, value: 30, to: calendar.startOfDay(for: referenceDate)) ?? referenceDate
        case .sixtyDays:
            return calendar.date(byAdding: .day, value: 60, to: calendar.startOfDay(for: referenceDate)) ?? referenceDate
        case .ninetyDays:
            return calendar.date(byAdding: .day, value: 90, to: calendar.startOfDay(for: referenceDate)) ?? referenceDate
        }
    }

    private static func recurringEvents(
        rules: [RecurringRule],
        resolvedOccurrenceKeys: Set<String>,
        referenceDate: Date,
        start: Date,
        end: Date,
        calendar: Calendar
    ) -> [CashFlowEvent] {
        var result: [CashFlowEvent] = []

        for rule in rules where rule.isActive {
            var cursor = rule.nextDueDate
            var iterations = 0
            while cursor <= referenceDate && iterations < 2_000 {
                iterations += 1
                guard let next = nextDate(for: rule, from: cursor, calendar: calendar), next > cursor else { break }
                cursor = next
            }

            while cursor >= start && cursor < end && iterations < 2_000 {
                iterations += 1
                if let endDate = rule.endDate, cursor > endDate { break }
                let key = RecurringOccurrence.key(ruleID: rule.id, scheduledDate: cursor, calendar: calendar)
                if !resolvedOccurrenceKeys.contains(key) {
                    result.append(
                        CashFlowEvent(
                            id: "recurring|\(key)",
                            date: cursor,
                            title: rule.isProtectedIncome ? "隐私收入" : rule.title,
                            signedAmount: rule.isExpense ? -rule.amount : rule.amount,
                            source: .recurring,
                            isEstimated: false,
                            isProtectedIncome: rule.isProtectedIncome
                        )
                    )
                }
                guard let next = nextDate(for: rule, from: cursor, calendar: calendar), next > cursor else { break }
                cursor = next
            }
        }
        return result
    }

    private static func installmentEvents(
        bills: [InstallmentBill],
        referenceDate: Date,
        start: Date,
        end: Date,
        calendar: Calendar
    ) -> [CashFlowEvent] {
        var result: [CashFlowEvent] = []
        for bill in bills where !bill.isCompleted {
            let firstUnpaid = bill.normalizedPaidInstallments
            for index in firstUnpaid..<bill.normalizedInstallmentCount {
                let scheduledDate = bill.repaymentDate(forInstallment: index, calendar: calendar)
                let date = scheduledDate <= referenceDate ? start : scheduledDate
                guard date >= start, date < end else { continue }
                result.append(
                    CashFlowEvent(
                        id: "installment|\(bill.id.uuidString)|\(index)",
                        date: date,
                        title: bill.name,
                        signedAmount: -bill.paymentAmount(forInstallment: index),
                        source: .installment,
                        isEstimated: false,
                        isProtectedIncome: false
                    )
                )
            }
        }
        return result
    }

    private static func routineExpensePerDay(
        transactions: [Transaction],
        referenceDate: Date,
        calendar: Calendar,
        lookbackDays: Int
    ) -> Decimal {
        let normalizedReference = calendar.startOfDay(for: referenceDate)
        let days = max(lookbackDays, 1)
        let cutoff = calendar.date(byAdding: .day, value: -days, to: normalizedReference) ?? normalizedReference
        let total = transactions.reduce(Decimal.zero) { total, transaction in
            guard transaction.date >= cutoff,
                  transaction.date < referenceDate,
                  transaction.isExpense,
                  transaction.recurringRule == nil,
                  BudgetScope.includesInDailyBudget(transaction) else {
                return total
            }
            return total + transaction.amount
        }
        return total / Decimal(days)
    }

    private static func nextDate(
        for rule: RecurringRule,
        from date: Date,
        calendar: Calendar
    ) -> Date? {
        let anchorDay = rule.anchorDay ?? (
            rule.frequency == .monthly || rule.frequency == .yearly
                ? calendar.component(.day, from: date)
                : nil
        )
        return rule.frequency.nextDate(from: date, anchorDay: anchorDay, calendar: calendar)
    }
}
