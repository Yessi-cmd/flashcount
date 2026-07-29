import Foundation

/// Pure projection of unresolved recurring-rule dates.
///
/// Both the interactive backfill flow and background Action Center queries use
/// this calculator, so "how many occurrences are pending" cannot drift between
/// the badge and the sheet.
enum RecurringOccurrencePreviewCalculator {
    static func pendingOccurrences(
        rules: [RecurringRule],
        occurrences: [RecurringOccurrence] = [],
        now: Date = .now,
        maxOccurrences: Int = 120,
        calendar: Calendar = .current
    ) -> [RecurringOccurrencePreview] {
        guard maxOccurrences > 0 else { return [] }

        let resolvedKeys = Set(occurrences.compactMap { occurrence in
            occurrence.status.isResolved ? occurrence.occurrenceKey : nil
        })
        var previews: [RecurringOccurrencePreview] = []

        for rule in rules where rule.isActive {
            guard previews.count < maxOccurrences else { break }
            var cursor = rule.nextDueDate
            var iterations = 0

            while cursor <= now && iterations < maxOccurrences * 4 {
                iterations += 1
                if let endDate = rule.endDate, cursor > endDate {
                    break
                }

                let key = RecurringOccurrence.key(
                    ruleID: rule.id,
                    scheduledDate: cursor,
                    calendar: calendar
                )
                if !resolvedKeys.contains(key) {
                    previews.append(
                        RecurringOccurrencePreview(
                            id: key,
                            ruleID: rule.id,
                            scheduledDate: cursor,
                            amount: rule.amount,
                            isExpense: rule.isExpense,
                            title: rule.title,
                            note: rule.note,
                            categoryID: rule.category?.id,
                            ledgerID: rule.ledger?.id,
                            isProtectedIncome: rule.isProtectedIncome
                        )
                    )
                }

                let anchorDay = rule.anchorDay ?? (
                    rule.frequency == .monthly || rule.frequency == .yearly
                        ? calendar.component(.day, from: cursor)
                        : nil
                )
                guard let next = rule.frequency.nextDate(
                    from: cursor,
                    anchorDay: anchorDay,
                    calendar: calendar
                ) else {
                    break
                }
                cursor = next
                if previews.count >= maxOccurrences { break }
            }
        }

        return previews.sorted {
            if $0.scheduledDate == $1.scheduledDate {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return $0.scheduledDate < $1.scheduledDate
        }
    }
}
