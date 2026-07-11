# Data integrity and quick-entry remediation

## Purpose

Fix the audit P0 risks around duplicate recurring entries, multiple cash-pool states, incomplete reminder backups, and non-functional quick-entry launch paths.

## Affected files

- `FlashCount/Services/FinanceServices/RecurringService.swift`
- `FlashCount/Services/FinanceServices/CashPoolService.swift`
- `FlashCount/Services/DataServices/DataBackupService.swift`
- `FlashCount/Services/DataServices/ReminderStore.swift`
- `FlashCount/Core/QuickAddIntent.swift`
- `FlashCount/FlashCountApp.swift`
- `FlashCount/Views/MainTabView.swift`
- `FlashCountWidget/`
- `project.yml`

## Behaviour changes

- Each recurring occurrence now advances its cursor and saves its transaction/cash-pool delta together; failures roll back the in-memory changes.
- Cash-pool access selects a deterministic primary state and removes historical duplicates on the next mutation. Backup merge no longer inserts a second state.
- Backups now contain reminders. Imported reminders are de-duplicated by UUID, saved locally, and future notifications are recreated.
- The Siri/Shortcuts intent sets a launch request consumed by `MainTabView`; the widget opens the `flashcount://quick-entry` URL. The project definition now includes a WidgetKit extension and a unit-test target.

## Verification planned

- Regenerate the Xcode project with XcodeGen.
- Build the app and test targets when the local simulator service is available.

## Remaining limitation

`SwiftData` and the reminder JSON file are separate stores, so an operating-system failure between their two saves cannot be made fully cross-store atomic. The database save is committed first; reminder write failure is surfaced to the caller.
