import Foundation

/// 由本地历史支出推断出的周期账单候选项。
struct RecurringSuggestion: Identifiable {
    let fingerprint: String
    let title: String
    let amount: Decimal
    let frequency: RecurringFrequency
    let nextDueDate: Date
    let occurrenceCount: Int
    let lastOccurrenceDate: Date
    let categoryID: UUID?
    let ledgerID: UUID?

    var id: String { fingerprint }
}

protocol RecurringSuggestionDismissalStoring {
    func load() -> Set<String>
    func dismiss(_ fingerprint: String)
}

/// 被用户忽略的模式只保存在本机偏好中。
struct UserDefaultsRecurringSuggestionDismissalStore: RecurringSuggestionDismissalStoring {
    static let defaultKey = "recurringSuggestionDismissals.v1"

    private let userDefaults: UserDefaults
    private let key: String

    init(userDefaults: UserDefaults = .standard, key: String = Self.defaultKey) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func load() -> Set<String> {
        Set(userDefaults.stringArray(forKey: key) ?? [])
    }

    func dismiss(_ fingerprint: String) {
        var fingerprints = load()
        fingerprints.insert(fingerprint)
        userDefaults.set(fingerprints.sorted(), forKey: key)
    }
}

/// 纯本地、只读的周期支出识别器。
enum RecurringSuggestionService {
    private struct GroupKey: Hashable {
        let categoryID: UUID?
        let ledgerID: UUID?
        let identity: String
        let normalizedNote: String
    }

    private struct Observation {
        let amount: Decimal
        let date: Date
        let displayTitle: String
    }

    private static let amountRatioTolerance = Decimal(string: "0.05")!
    private static let minimumAmountTolerance = Decimal(string: "0.01")!

    static func suggestions(
        transactions: [Transaction],
        existingRules: [RecurringRule],
        dismissedFingerprints: Set<String> = [],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [RecurringSuggestion] {
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let nextReferenceDay = calendar.date(byAdding: .day, value: 1, to: referenceDay) ?? referenceDate
        var groups: [GroupKey: [Observation]] = [:]

        for transaction in transactions where
            transaction.isExpense &&
            transaction.recurringRule == nil &&
            transaction.amount > 0 &&
            transaction.date < nextReferenceDay &&
            transaction.category?.isArchived != true
        {
            let normalizedNote = normalize(transaction.note)
            let identity = normalizedNote.isEmpty
                ? "amount:\(canonicalAmount(transaction.amount))"
                : "note:\(normalizedNote)"
            let key = GroupKey(
                categoryID: transaction.category?.id,
                ledgerID: transaction.ledger?.id,
                identity: identity,
                normalizedNote: normalizedNote
            )
            let cleanNote = transaction.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayTitle = cleanNote.isEmpty
                ? (transaction.category?.name ?? "固定支出")
                : cleanNote
            groups[key, default: []].append(
                Observation(amount: transaction.amount, date: transaction.date, displayTitle: displayTitle)
            )
        }

        var results: [RecurringSuggestion] = []
        let frequencies: [RecurringFrequency] = [.daily, .weekly, .monthly, .yearly]

        for (key, observations) in groups {
            let ordered = observations.sorted { $0.date < $1.date }

            for frequency in frequencies {
                let run = latestMatchingRun(in: ordered, frequency: frequency, calendar: calendar)
                guard run.count >= minimumOccurrences(for: frequency),
                      amountsAreStable(in: run),
                      let last = run.last,
                      isFresh(last.date, frequency: frequency, referenceDate: referenceDate, calendar: calendar)
                else {
                    continue
                }

                let amount = medianAmount(in: run)
                let fingerprint = makeFingerprint(key: key, frequency: frequency)
                guard !dismissedFingerprints.contains(fingerprint),
                      let nextDueDate = nextDueDate(
                        after: last.date,
                        frequency: frequency,
                        run: run,
                        referenceDate: referenceDate,
                        calendar: calendar
                      )
                else {
                    break
                }

                let suggestion = RecurringSuggestion(
                    fingerprint: fingerprint,
                    title: last.displayTitle,
                    amount: amount,
                    frequency: frequency,
                    nextDueDate: nextDueDate,
                    occurrenceCount: run.count,
                    lastOccurrenceDate: last.date,
                    categoryID: key.categoryID,
                    ledgerID: key.ledgerID
                )

                if !isCovered(suggestion, normalizedNote: key.normalizedNote, by: existingRules) {
                    results.append(suggestion)
                }
                break
            }
        }

        return results.sorted {
            if $0.nextDueDate != $1.nextDueDate { return $0.nextDueDate < $1.nextDueDate }
            if $0.occurrenceCount != $1.occurrenceCount { return $0.occurrenceCount > $1.occurrenceCount }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private static func latestMatchingRun(
        in observations: [Observation],
        frequency: RecurringFrequency,
        calendar: Calendar
    ) -> [Observation] {
        guard !observations.isEmpty else { return [] }
        var startIndex = observations.count - 1

        while startIndex > 0 {
            let previous = observations[startIndex - 1]
            let current = observations[startIndex]
            guard intervalMatches(from: previous.date, to: current.date, frequency: frequency, calendar: calendar) else {
                break
            }
            startIndex -= 1
        }

        return Array(observations[startIndex...])
    }

    private static func intervalMatches(
        from earlier: Date,
        to later: Date,
        frequency: RecurringFrequency,
        calendar: Calendar
    ) -> Bool {
        let first = calendar.startOfDay(for: earlier)
        let second = calendar.startOfDay(for: later)
        guard second > first else { return false }

        switch frequency {
        case .daily:
            return calendar.dateComponents([.day], from: first, to: second).day == 1
        case .weekly:
            guard let days = calendar.dateComponents([.day], from: first, to: second).day else { return false }
            return (6...8).contains(days)
        case .monthly:
            guard monthOrdinal(for: second, calendar: calendar) - monthOrdinal(for: first, calendar: calendar) == 1 else {
                return false
            }
            return matchingDayPosition(first, second, calendar: calendar)
        case .yearly:
            let firstComponents = calendar.dateComponents([.year, .month], from: first)
            let secondComponents = calendar.dateComponents([.year, .month], from: second)
            guard let firstYear = firstComponents.year,
                  let secondYear = secondComponents.year,
                  firstComponents.month == secondComponents.month,
                  secondYear - firstYear == 1
            else {
                return false
            }
            return matchingDayPosition(first, second, calendar: calendar)
        }
    }

    private static func matchingDayPosition(_ first: Date, _ second: Date, calendar: Calendar) -> Bool {
        if isLastDayOfMonth(first, calendar: calendar) && isLastDayOfMonth(second, calendar: calendar) {
            return true
        }
        let firstDay = calendar.component(.day, from: first)
        let secondDay = calendar.component(.day, from: second)
        return abs(firstDay - secondDay) <= 3
    }

    private static func isLastDayOfMonth(_ date: Date, calendar: Calendar) -> Bool {
        guard let range = calendar.range(of: .day, in: .month, for: date) else { return false }
        return calendar.component(.day, from: date) == range.count
    }

    private static func monthOrdinal(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.year, .month], from: date)
        return (components.year ?? 0) * 12 + (components.month ?? 0)
    }

    private static func minimumOccurrences(for frequency: RecurringFrequency) -> Int {
        switch frequency {
        case .daily: return 5
        case .weekly, .monthly: return 3
        case .yearly: return 2
        }
    }

    private static func amountsAreStable(in observations: [Observation]) -> Bool {
        let median = medianAmount(in: observations)
        let tolerance = max(minimumAmountTolerance, abs(median) * amountRatioTolerance)
        return observations.allSatisfy { abs($0.amount - median) <= tolerance }
    }

    private static func medianAmount(in observations: [Observation]) -> Decimal {
        let amounts = observations.map(\.amount).sorted()
        guard !amounts.isEmpty else { return 0 }
        return amounts[(amounts.count - 1) / 2]
    }

    private static func isFresh(
        _ lastOccurrence: Date,
        frequency: RecurringFrequency,
        referenceDate: Date,
        calendar: Calendar
    ) -> Bool {
        let lastDay = calendar.startOfDay(for: lastOccurrence)
        let referenceDay = calendar.startOfDay(for: referenceDate)
        guard lastDay <= referenceDay else { return false }

        switch frequency {
        case .daily:
            return (calendar.dateComponents([.day], from: lastDay, to: referenceDay).day ?? .max) <= 3
        case .weekly:
            return (calendar.dateComponents([.day], from: lastDay, to: referenceDay).day ?? .max) <= 21
        case .monthly:
            return monthOrdinal(for: referenceDay, calendar: calendar) - monthOrdinal(for: lastDay, calendar: calendar) <= 3
        case .yearly:
            let years = calendar.dateComponents([.year], from: lastDay, to: referenceDay).year ?? .max
            return years <= 2
        }
    }

    private static func nextDueDate(
        after lastOccurrence: Date,
        frequency: RecurringFrequency,
        run: [Observation],
        referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let anchorDay: Int? = {
            guard frequency == .monthly || frequency == .yearly else { return nil }
            if run.allSatisfy({ isLastDayOfMonth($0.date, calendar: calendar) }) { return 31 }
            let days = run.map { calendar.component(.day, from: $0.date) }.sorted()
            return days[(days.count - 1) / 2]
        }()

        var cursor = lastOccurrence
        for _ in 0..<1_500 {
            guard let candidate = frequency.nextDate(from: cursor, anchorDay: anchorDay, calendar: calendar) else {
                return nil
            }
            if calendar.startOfDay(for: candidate) >= referenceDay {
                return candidate
            }
            cursor = candidate
        }
        return nil
    }

    private static func isCovered(
        _ suggestion: RecurringSuggestion,
        normalizedNote: String,
        by rules: [RecurringRule]
    ) -> Bool {
        rules.contains { rule in
            guard rule.isExpense,
                  rule.frequency == suggestion.frequency,
                  rule.category?.id == suggestion.categoryID,
                  rule.ledger?.id == suggestion.ledgerID,
                  amountsMatch(rule.amount, suggestion.amount)
            else {
                return false
            }

            guard !normalizedNote.isEmpty else { return true }
            return normalize(rule.title) == normalizedNote || normalize(rule.note) == normalizedNote
        }
    }

    private static func amountsMatch(_ lhs: Decimal, _ rhs: Decimal) -> Bool {
        let tolerance = max(minimumAmountTolerance, abs(rhs) * amountRatioTolerance)
        return abs(lhs - rhs) <= tolerance
    }

    private static func makeFingerprint(key: GroupKey, frequency: RecurringFrequency) -> String {
        [
            "v1",
            key.categoryID?.uuidString.lowercased() ?? "none",
            key.ledgerID?.uuidString.lowercased() ?? "none",
            frequency.rawValue,
            key.identity,
        ].joined(separator: "|")
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_CN"))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private static func canonicalAmount(_ amount: Decimal) -> String {
        NSDecimalNumber(decimal: amount).stringValue
    }
}
