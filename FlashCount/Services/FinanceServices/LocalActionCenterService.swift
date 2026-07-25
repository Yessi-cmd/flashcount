import Foundation

enum LocalActionKind: String, CaseIterable, Identifiable {
    case budgetOverrun
    case recurringDebit
    case installmentDue
    case recurringSuggestion
    case incompleteReminder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .budgetOverrun: return "预算风险"
        case .recurringDebit: return "近期扣款"
        case .installmentDue: return "分期到期"
        case .recurringSuggestion: return "周期建议"
        case .incompleteReminder: return "未完成提醒"
        }
    }

    var iconName: String {
        switch self {
        case .budgetOverrun: return "exclamationmark.triangle.fill"
        case .recurringDebit: return "repeat.circle.fill"
        case .installmentDue: return "creditcard.trianglebadge.exclamationmark.fill"
        case .recurringSuggestion: return "sparkles"
        case .incompleteReminder: return "bell.badge.fill"
        }
    }
}

enum LocalActionDestination: String, Hashable, Identifiable {
    case budget
    case recurringRules
    case installmentBills
    case reminders

    var id: String { rawValue }
}

enum LocalActionSeverity: Int, Comparable {
    case overdue = 0
    case urgent = 1
    case upcoming = 2
    case recommendation = 3

    static func < (lhs: LocalActionSeverity, rhs: LocalActionSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct LocalActionItem: Identifiable, Equatable {
    let id: String
    let kind: LocalActionKind
    let destination: LocalActionDestination
    let title: String
    let detail: String
    let date: Date?
    let amount: Decimal?
    let severity: LocalActionSeverity
    let isPrivacySensitiveAmount: Bool

    var accessibilityText: String {
        var parts = [title, detail]
        if let amount {
            parts.append(amount.formattedCurrency)
        }
        return parts.joined(separator: "，")
    }
}

struct LocalActionSection: Identifiable, Equatable {
    let kind: LocalActionKind
    let items: [LocalActionItem]

    var id: String { kind.id }
    var title: String { kind.title }
}

struct LocalActionCenterSnapshot: Equatable {
    let sections: [LocalActionSection]

    var totalCount: Int {
        sections.reduce(0) { $0 + $1.items.count }
    }

    var isEmpty: Bool { sections.isEmpty }
}

/// Aggregates local data into actionable, page-level destinations.
///
/// This service is deliberately read-only. It does not insert, update, or
/// delete SwiftData models, and every date-dependent input can be injected for
/// deterministic tests.
enum LocalActionCenterService {
    static let defaultUpcomingDays = 30

    static func snapshot(
        budgets: [Budget],
        transactions: [Transaction],
        recurringRules: [RecurringRule],
        occurrences: [RecurringOccurrence],
        pendingBackfill: [RecurringOccurrencePreview],
        installmentBills: [InstallmentBill],
        reminders: [ReminderItem],
        dismissedSuggestionFingerprints: Set<String> = [],
        referenceDate: Date = .now,
        payday: Int = 1,
        weekendMultiplier: Decimal = 1,
        upcomingDays: Int = defaultUpcomingDays,
        calendar: Calendar = .current
    ) -> LocalActionCenterSnapshot {
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let upcomingEnd = calendar.date(
            byAdding: .day,
            value: max(upcomingDays, 0),
            to: referenceDay
        ) ?? referenceDay

        var grouped: [LocalActionKind: [LocalActionItem]] = [:]
        appendBudgetItem(
            to: &grouped,
            budgets: budgets,
            transactions: transactions,
            referenceDate: referenceDate,
            payday: payday,
            weekendMultiplier: weekendMultiplier,
            calendar: calendar
        )
        appendRecurringItems(
            to: &grouped,
            recurringRules: recurringRules,
            occurrences: occurrences,
            pendingBackfill: pendingBackfill,
            referenceDate: referenceDate,
            referenceDay: referenceDay,
            upcomingEnd: upcomingEnd,
            payday: payday,
            calendar: calendar
        )
        appendInstallmentItems(
            to: &grouped,
            bills: installmentBills,
            referenceDay: referenceDay,
            upcomingEnd: upcomingEnd,
            calendar: calendar
        )
        appendSuggestionItems(
            to: &grouped,
            transactions: transactions,
            recurringRules: recurringRules,
            dismissedSuggestionFingerprints: dismissedSuggestionFingerprints,
            referenceDate: referenceDate,
            calendar: calendar
        )
        appendReminderItems(
            to: &grouped,
            reminders: reminders,
            referenceDay: referenceDay,
            calendar: calendar
        )

        let orderedKinds: [LocalActionKind] = [
            .budgetOverrun,
            .recurringDebit,
            .installmentDue,
            .recurringSuggestion,
            .incompleteReminder,
        ]

        let sections = orderedKinds.compactMap { kind -> LocalActionSection? in
            guard let items = grouped[kind], !items.isEmpty else { return nil }
            return LocalActionSection(kind: kind, items: sort(items))
        }
        return LocalActionCenterSnapshot(sections: sections)
    }

    private static func appendBudgetItem(
        to grouped: inout [LocalActionKind: [LocalActionItem]],
        budgets: [Budget],
        transactions: [Transaction],
        referenceDate: Date,
        payday: Int,
        weekendMultiplier: Decimal,
        calendar: Calendar
    ) {
        guard let reminder = BudgetReminderService.reminder(
            budgets: budgets,
            transactions: transactions,
            ledger: nil,
            referenceDate: referenceDate,
            payday: payday,
            weekendMultiplier: weekendMultiplier,
            calendar: calendar
        ), reminder.alertLevel == .danger else { return }

        let analysis = reminder.analysis
        let actualOverAmount = max(analysis.totalSpent - analysis.budgetLimit, 0)
        let projectedOverAmount = analysis.projectedOverAmount
        let amount: Decimal?
        let detail: String
        if actualOverAmount > 0 {
            amount = actualOverAmount
            detail = "\(reminder.title) · 已超出 \(actualOverAmount.formattedCurrency)"
        } else if projectedOverAmount > 0 {
            amount = projectedOverAmount
            detail = "\(reminder.title) · 预计超支 \(projectedOverAmount.formattedCurrency)"
        } else {
            amount = nil
            detail = reminder.shortMessage
        }
        let actionAmount = amount.flatMap { $0 > 0 ? $0 : nil }
        let item = LocalActionItem(
            id: "budget.overrun",
            kind: .budgetOverrun,
            destination: .budget,
            title: reminder.title,
            detail: detail,
            date: analysis.periodEnd,
            amount: actionAmount,
            severity: .urgent,
            isPrivacySensitiveAmount: false
        )
        grouped[.budgetOverrun, default: []].append(item)
    }

    private static func appendRecurringItems(
        to grouped: inout [LocalActionKind: [LocalActionItem]],
        recurringRules: [RecurringRule],
        occurrences: [RecurringOccurrence],
        pendingBackfill: [RecurringOccurrencePreview],
        referenceDate: Date,
        referenceDay: Date,
        upcomingEnd: Date,
        payday: Int,
        calendar: Calendar
    ) {
        let forecast = CashFlowForecastService.forecast(
            cashPoolItems: [],
            cashPoolState: nil,
            recurringRules: recurringRules,
            occurrences: occurrences,
            installmentBills: [],
            transactions: [],
            referenceDate: referenceDate,
            horizon: .thirtyDays,
            mode: .fixedOnly,
            payday: payday,
            calendar: calendar
        )

        for event in forecast.events where
            event.source == .recurring &&
            event.isExpense &&
            event.date >= referenceDay &&
            event.date < upcomingEnd
        {
            let item = LocalActionItem(
                id: event.id,
                kind: .recurringDebit,
                destination: .recurringRules,
                title: event.title,
                detail: "\(event.date.shortDateString) · 周期扣款",
                date: event.date,
                amount: abs(event.signedAmount),
                severity: calendar.isDate(event.date, inSameDayAs: referenceDay) ? .urgent : .upcoming,
                isPrivacySensitiveAmount: false
            )
            grouped[.recurringDebit, default: []].append(item)
        }

        for preview in pendingBackfill where preview.isExpense {
            let severity: LocalActionSeverity = calendar.isDate(
                preview.scheduledDate,
                inSameDayAs: referenceDay
            ) ? .urgent : .overdue
            let item = LocalActionItem(
                id: "recurring.pending|\(preview.id)",
                kind: .recurringDebit,
                destination: .recurringRules,
                title: preview.title,
                detail: "\(preview.scheduledDate.shortDateString) · 待补账",
                date: preview.scheduledDate,
                amount: preview.amount,
                severity: severity,
                isPrivacySensitiveAmount: false
            )
            grouped[.recurringDebit, default: []].append(item)
        }
    }

    private static func appendInstallmentItems(
        to grouped: inout [LocalActionKind: [LocalActionItem]],
        bills: [InstallmentBill],
        referenceDay: Date,
        upcomingEnd: Date,
        calendar: Calendar
    ) {
        for bill in bills where !bill.isArchived && !bill.isCompleted {
            guard let dueDate = bill.nextRepaymentDate(calendar: calendar),
                  dueDate < upcomingEnd else { continue }

            let isOverdue = dueDate < referenceDay
            let isDueToday = calendar.isDate(dueDate, inSameDayAs: referenceDay)
            let installmentNumber = bill.normalizedPaidInstallments + 1
            let detail: String
            if isOverdue {
                detail = "已逾期 · 第\(installmentNumber)/\(bill.normalizedInstallmentCount)期"
            } else if isDueToday {
                detail = "今天还款 · 第\(installmentNumber)/\(bill.normalizedInstallmentCount)期"
            } else {
                detail = "\(dueDate.shortDateString) · 第\(installmentNumber)/\(bill.normalizedInstallmentCount)期"
            }

            let item = LocalActionItem(
                id: "installment|\(bill.id.uuidString)",
                kind: .installmentDue,
                destination: .installmentBills,
                title: bill.name,
                detail: detail,
                date: dueDate,
                amount: bill.paymentAmount(forInstallment: bill.normalizedPaidInstallments),
            severity: isOverdue ? .overdue : (isDueToday ? .urgent : .upcoming),
                isPrivacySensitiveAmount: true
            )
            grouped[.installmentDue, default: []].append(item)
        }
    }

    private static func appendSuggestionItems(
        to grouped: inout [LocalActionKind: [LocalActionItem]],
        transactions: [Transaction],
        recurringRules: [RecurringRule],
        dismissedSuggestionFingerprints: Set<String>,
        referenceDate: Date,
        calendar: Calendar
    ) {
        let suggestions = RecurringSuggestionService.suggestions(
            transactions: transactions,
            existingRules: recurringRules,
            dismissedFingerprints: dismissedSuggestionFingerprints,
            referenceDate: referenceDate,
            calendar: calendar
        )

        for suggestion in suggestions {
            let item = LocalActionItem(
                id: "suggestion|\(suggestion.fingerprint)",
                kind: .recurringSuggestion,
                destination: .recurringRules,
                title: suggestion.title,
                detail: "\(suggestion.frequency.rawValue) · 已出现 \(suggestion.occurrenceCount) 次 · 下次 \(suggestion.nextDueDate.shortDateString)",
                date: suggestion.nextDueDate,
                amount: suggestion.amount,
                severity: .recommendation,
                isPrivacySensitiveAmount: false
            )
            grouped[.recurringSuggestion, default: []].append(item)
        }
    }

    private static func appendReminderItems(
        to grouped: inout [LocalActionKind: [LocalActionItem]],
        reminders: [ReminderItem],
        referenceDay: Date,
        calendar: Calendar
    ) {
        for reminder in reminders where !reminder.isCompleted {
            let isOverdue = reminder.dueDate < referenceDay
            let isDueToday = calendar.isDate(reminder.dueDate, inSameDayAs: referenceDay)
            let severity: LocalActionSeverity = isOverdue ? .overdue : (isDueToday ? .urgent : .upcoming)
            let item = LocalActionItem(
                id: "reminder|\(reminder.id.uuidString)",
                kind: .incompleteReminder,
                destination: .reminders,
                title: reminder.title,
                detail: reminder.dueDate.reminderDateTimeString,
                date: reminder.dueDate,
                amount: nil,
                severity: severity,
                isPrivacySensitiveAmount: false
            )
            grouped[.incompleteReminder, default: []].append(item)
        }
    }

    private static func sort(_ items: [LocalActionItem]) -> [LocalActionItem] {
        items.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
            switch (lhs.date, rhs.date) {
            case let (left?, right?) where left != right:
                return left < right
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            default:
                break
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }
}
