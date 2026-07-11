# Import and recurring fetch errors

## Purpose

Eliminate remaining silent fetch-to-empty-data conversions in backup import and recurring processing.

## Affected files

- `FlashCount/Services/DataServices/DataBackupService.swift`
- `FlashCount/Services/FinanceServices/RecurringService.swift`

## Behaviour changes

- Import now aborts before modifying data when any existing-record lookup fails.
- Recurring processing logs a concrete read error and returns without creating entries when its rule query fails.

## Verification

`git diff --check` passed before this batch; project regeneration will be repeated with the final verification pass.
