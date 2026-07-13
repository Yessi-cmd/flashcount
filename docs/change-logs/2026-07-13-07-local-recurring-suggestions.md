# Local recurring-spend suggestions

## Purpose

Help users turn repeated manual expenses into recurring rules without sending transaction data off device.

## Affected files

- `FlashCount/Services/FinanceServices/RecurringSuggestionService.swift`
- `FlashCount/Views/Recurring/RecurringRulesView.swift`
- `FlashCount/Views/Recurring/AddRecurringRuleView.swift`
- `FlashCountTests/RecurringSuggestionServiceTests.swift`
- `FlashCountUITests/FlashCountSmokeTests.swift`

## Behaviour changes

- The recurring-rules screen analyzes local manual expenses and surfaces likely daily, weekly, monthly, or yearly patterns.
- Detection groups normalized notes by category and ledger, requires stable dates and amounts, handles month-end dates, and ignores generated recurring transactions.
- Existing matching recurring rules suppress duplicate suggestions.
- Users can prefill a new recurring rule from a suggestion or permanently ignore that pattern on the current device.
- Editing an existing monthly or yearly rule now refreshes its day anchor when its frequency or next date changes.
- The wheel-dismissal smoke test now taps a verified blank area of the overlay and waits for its closing animation, making the check independent of navigation-bar height.

## Verification performed

- Added deterministic tests for month-end monthly detection, weekly tolerance, inconsistent dates, variable amounts, existing-rule suppression, generated-transaction exclusion, and dismissal persistence.
- `xcodegen generate` completed successfully and regenerated the Xcode project from `project.yml`.
- An unsigned Debug build for the generic iOS Simulator destination succeeded, including embedded-widget validation.
- All 59 unit tests passed on an iPhone 17 Pro simulator running iOS 26.2.
- All 4 UI smoke tests passed on the same simulator.
- `git diff --check` completed without whitespace errors; the generated project lists the app, unit-test, UI-test, and Widget targets.

## Remaining limitations

- Suggestions deliberately require repeated, recent, stable expenses, so irregular bills and frequently changing amounts may still require manual rule creation.
- Ignored suggestion fingerprints are device-local preferences and are not exported in data backups.
