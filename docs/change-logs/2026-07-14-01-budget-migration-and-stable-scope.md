# Budget migration and stable daily scope

## Purpose

Normalize legacy single-ledger budgets for the global budget UI and make the built-in daily-budget range resilient to category renaming.

## Affected files

- `FlashCount/Services/DataServices/DefaultDataService.swift`
- `FlashCount/Services/BudgetServices/BudgetReminderService.swift`
- `FlashCount/Views/Budget/DailyBudgetScopeView.swift`
- `FlashCountTests/FinanceDomainTests.swift`

## Behaviour changes

- Single-ledger startup still moves transactions and recurring rules to the primary ledger, but now detaches every budget from its ledger, including budgets already attached to the primary ledger.
- Budget normalization preserves every record and its ID, amount, year, month, category ID, and creation date.
- Built-in daily-budget membership is keyed by `Category.defaultKey` rather than mutable category names.
- Before default keys are backfilled, legacy keyless expense categories receive an explicit include/exclude override matching the old name-based behavior; existing overrides remain unchanged.
- Restoring the scope defaults clears overrides only for categories with a stable default key. Keyless categories are explicitly excluded.

## Verification

- Added in-memory SwiftData coverage for budget preservation and service visibility, stable-key behavior after renaming, keyless-name exclusion, legacy scope freezing, override preservation, and repeat-stage idempotence.
- Full unit and UI verification passed on the iPhone 17 iOS 26.2 simulator: 72 unit tests and 5 UI tests, with zero failures.
- Debug and Release simulator builds passed without compiler warnings.
- `xcodegen generate` and `git diff --check` passed.
