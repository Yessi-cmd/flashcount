# Report targets, history, and presentation

## Purpose

Connect scheduled report targets to production navigation and complete the shared daily, weekly, monthly, and yearly report experience.

## Affected files

- `FlashCount/Core/ReportRoute.swift`
- `FlashCount/FlashCountApp.swift`
- `FlashCount/Services/BudgetServices/ReportBudgetSnapshotService.swift`
- `FlashCount/Services/FinanceServices/ReportPeriodCalculator.swift`
- `FlashCount/Services/FinanceServices/ReportService.swift`
- `FlashCount/Services/SystemServices/ReminderNotificationService.swift`
- `FlashCount/Views/MainTabView.swift`
- `FlashCount/Views/Report/ReportPresentation.swift`
- `FlashCount/Views/Report/ReportView.swift`
- `FlashCountTests/AppRoutingTests.swift`
- `FlashCountTests/ReportDomainTests.swift`
- `FlashCountUITests/FlashCountSmokeTests.swift`

## Behaviour changes

- Report notifications now retain their delivered date and open the report represented by that delivery; normal tabs and URL deep links continue to open the current period.
- Reports support adjacent completed-period navigation without allowing navigation into the future.
- Streak calculations stop at the report range's exclusive end.
- All four periods use typed hour/day/week/month buckets, dynamic titles, correct half-open range labels, semantic income/expense change colors, and truthful percentage formatting.
- The report page now provides loading, empty, refresh, retry, chart-detail, and partial-data states, refreshes on foreground activation and local midnight, and observes a bounded date envelope.
- A separate pay-cycle budget card follows the report anchor and explicitly shows pay-cycle values instead of comparing a calendar-month report directly with a pay-cycle budget.

## Verification

- Added domain, routing, budget-anchor, presentation, and UI navigation coverage.
- Full unit and UI verification passed on the iPhone 17 iOS 26.2 simulator: 72 unit tests and 5 UI tests, with zero failures.
- Debug and Release simulator builds passed without compiler warnings.
- `xcodegen generate` and `git diff --check` passed.

## Remaining limitations

- Reports remain calculated from local transactions rather than persisted as historical snapshots.
- Chart coordinates use `Double` at the Swift Charts rendering boundary; all stored and aggregated money remains `Decimal`.
