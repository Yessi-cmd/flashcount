# Error handling and report refresh

## Purpose

Resolve P2 issues where failed saves left mutated SwiftData objects in memory, failed report reads appeared as empty reports, and a report could remain stale after editing transactions.

## Affected files

- `FlashCount/Views/QuickEntry/QuickEntryView.swift`
- `FlashCount/Views/Ledger/EditTransactionView.swift`
- `FlashCount/Views/Ledger/LedgerView.swift`
- `FlashCount/Services/DataServices/DataBackupService.swift`
- `FlashCount/Services/FinanceServices/ReportService.swift`
- `FlashCount/Views/Report/ReportView.swift`

## Behaviour changes

- Failed transaction mutations now roll back their in-memory SwiftData changes.
- Backup export now propagates fetch errors instead of silently exporting an empty section.
- Report data fetch failures are surfaced in an alert instead of being interpreted as no transactions.
- ReportView observes a transaction revision and regenerates when transaction content changes.

## Verification

The generated project contains the app, WidgetKit extension, and unit-test target. Full compilation remains blocked by the local Xcode asset-catalog service, which has no available simulator runtime.
