# FlashCount AI Project Context

Last scanned: 2026-06-28
Last updated after implementation: 2026-06-28
Repository: `/Users/zhongyan/Code/Playground/flashcount`
Current branch at scan time: `main`

This file is for AI coding tools that need to understand the project quickly before making changes.

## Project Summary

FlashCount is a local-first iOS bookkeeping app written in SwiftUI. It focuses on personal fast expense entry, recurring bills, budget warnings, reports, asset tracking, and local future reminders. The README states that all user data stays on device, with no network requests, ads, or tracking.

Primary stack:

- SwiftUI for UI.
- SwiftData for local persistence.
- Swift Charts for report and asset charts.
- App Intents for Siri/Shortcuts entry points.
- UserNotifications for local reminders.
- XcodeGen via `project.yml` for project generation.

Declared requirements:

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9

## Build And Project Setup

The canonical project config appears to be `project.yml`.

Useful commands:

```bash
xcodegen generate
xcodebuild -list -project FlashCount.xcodeproj
open FlashCount.xcodeproj
```

Observed with `xcodebuild -list -project FlashCount.xcodeproj`:

- Target: `FlashCount`
- Scheme: `FlashCount`
- Build configurations: `Debug`, `Release`

Important: `FlashCountWidget/` exists, but it is not referenced by `project.yml` or `FlashCount.xcodeproj` at scan time. `xcodebuild -list` reports only the main app target. If implementing or fixing Widget behavior, first add a Widget Extension target to `project.yml` and regenerate the Xcode project.

There are no test targets or test files in the repository at scan time.

## Worktree State At Scan Time

`git status --short` showed two modified files:

- `FlashCount/Services/DataBackupService.swift`
- `FlashCount/Views/Asset/PhysicalAssetView.swift`

Do not overwrite these without checking the diff first. Observed changes:

- `DataBackupService.swift`: import now de-duplicates categories by `name + isExpense`, de-duplicates ledgers by name, and assigns imported transactions with missing/unmatched ledgers to a default ledger fallback.
- `PhysicalAssetView.swift`: active and archived physical assets gained context menus for edit/archive/restore/delete actions.

This AI context file was added after those changes were already present.

## Top-Level Directory Map

- `README.md`: product overview and setup instructions.
- `project.yml`: XcodeGen configuration for the main app.
- `ExportOptions.plist`: export/signing options.
- `FlashCount/`: main app source.
- `FlashCountWidget/`: WidgetKit source files, currently not wired into the generated project.
- `FlashCount.xcodeproj/`: generated Xcode project. Prefer editing `project.yml` instead of hand-editing this directory.

## App Entry And Persistence

Main entry:

- `FlashCount/FlashCountApp.swift`

The app creates a SwiftData model container for:

- `Transaction`
- `Category`
- `Ledger`
- `RecurringRule`
- `Budget`
- `Asset`
- `PhysicalAsset`

`MainTabView` is the root UI. Color scheme is controlled by `@AppStorage("appearance")` through `AppearancePreference`; the default is now light.

Startup seed behavior:

- `DefaultDataService` prepares data from the environment `modelContext`.
- It non-destructively inserts missing default data and preserves existing user data.
- Default ledger seeding now creates only `生活`. Empty legacy `生意` ledgers are removed on startup only if they have no transactions, budgets, or recurring rules.
- It calls `RecurringService.processAllDueRules()` during app startup.
- It configures the local notification delegate so reminder notifications can present while the app is foreground.

## Main Navigation

Root view:

- `FlashCount/Views/MainTabView.swift`

Tabs:

- `LedgerView`: personal transaction list and reminder entry.
- `BudgetView`: monthly budget warning.
- Center plus button: opens `QuickEntryView`, except on the asset tab where it opens `AddAssetView`.
- `ReportView`: weekly/monthly reports.
- `AssetDashboardView`: financial and physical asset views.

First launch:

- `OnboardingView` is shown via `@AppStorage("hasCompletedOnboarding")`.
- The flag is set to true as soon as onboarding is presented, not when the user taps the final button.

## Data Model Overview

All persistent models use SwiftData `@Model`.

### Transaction

File: `FlashCount/Models/Transaction.swift`

- Amounts are stored as positive `Decimal`.
- `isExpense` decides whether the transaction is expense or income.
- `signedAmount` returns negative for expenses and positive for income.
- Optional relationships: `category`, `ledger`, `recurringRule`.

### Category

File: `FlashCount/Models/Category.swift`

- Has name, SF Symbol icon, hex color, expense/income flag, sort order, archive flag.
- Default expense and income categories are defined here.
- Relationship delete rules nullify category references from transactions and recurring rules.

### Ledger

File: `FlashCount/Models/Ledger.swift`

- Legacy model for a bookkeeping context; the current product UI is single-ledger/personal.
- Default ledger is `生活`.
- Deleting a ledger cascades to its transactions and budgets.
- Recurring rules are nullified when a ledger is removed.

### Budget

File: `FlashCount/Models/Budget.swift`

- Monthly budget per ledger, optionally scoped by `categoryId`.
- UI currently uses the ledger-level budget where `categoryId == nil`.
- `BudgetAlertLevel` defines healthy/warning/danger states.

### RecurringRule

File: `FlashCount/Models/RecurringRule.swift`

- Frequencies: daily, weekly, monthly, yearly.
- Tracks `nextDueDate`, amount, active state, optional category and ledger.
- Generated transactions link back through `recurringRule`.

### Asset

File: `FlashCount/Models/Asset.swift`

- Financial accounts such as bank card, cash, investment, credit card, loan, online pay, other.
- Credit card and loan are liabilities.
- `signedBalance` is negative for liabilities and positive for assets.

### PhysicalAsset

File: `FlashCount/Models/PhysicalAsset.swift`

- Tracks real-world assets such as phone, laptop, car, house.
- Stores purchase price/date, salvage value, target daily cost, optional sold price/date, note, archive flag.
- Calculates days held, depreciable cost, current daily cost, progress to target, current value, actual profit, and actual daily cost.

### ReminderItem

File: `FlashCount/Models/ReminderItem.swift`

- Codable local reminder model stored separately from SwiftData to avoid schema migration risk.
- Fields include title, note, due date, intensity, completion state, created date, and completed date.
- `ReminderIntensity` supports normal reminders and strong reminders. Strong reminders schedule several notifications after the due time.

## Services And Helpers

### RecurringService

File: `FlashCount/Services/RecurringService.swift`

- Fetches active recurring rules.
- Generates missing transactions while `nextDueDate <= now`.
- Advances `nextDueDate` by rule frequency.
- Saves once at the end.

Current behavior: this service is called by `DefaultDataService` during app startup.

### BudgetAnalyzer

File: `FlashCount/Services/BudgetAnalyzer.swift`

- Pure calculation helper for monthly budget analytics.
- Computes elapsed days, remaining days, daily average, projected total, remaining budget, daily allowance, usage percentage, and alert level.
- Good candidate for unit tests if tests are added.

### ReportService

File: `FlashCount/Services/ReportService.swift`

- Generates weekly or monthly report data.
- Computes current and previous period totals, category breakdown, daily expenses, continuous logging streak, and text insights.
- Currently reports across all transactions, not scoped by ledger.

### DataBackupService

File: `FlashCount/Services/DataBackupService.swift`

- Exports/imports full app data as JSON.
- Backup schema version currently `1.2.0`.
- DTOs convert `Decimal` to `Double`, so be careful if exact decimal precision becomes a product requirement.
- Import order: categories and ledgers first, then transactions, assets, physical assets, recurring rules, budgets.

### ErrorHandling And Data Repair

File: `FlashCount/Helpers/ErrorHandling.swift`

- `safeSave(_:)` wraps `ModelContext.save()` and returns a localized error string.
- `SaveErrorAlert` displays save errors.
- `DataRepairService` repairs missing categories, invalid amounts, and missing ledgers.
- `HapticManager` centralizes UIKit haptic feedback.

### Design System And Extensions

Files:

- `FlashCount/Helpers/DesignSystem.swift`
- `FlashCount/Helpers/Extensions.swift`

Conventions:

- Light, semantic UI with `DesignSystem.surfaceBackground`, `cardBackground`, gradients, and `glassCard()`.
- Hex color support via `Color(hex:)`.
- Money formatting lives on `Decimal`.
- Date display helpers live on `Date`.
- `CalendarView.swift` also defines a local `Decimal.compactAmount` extension for tiny calendar cells.

## Main Feature Areas

### Quick Entry

File: `FlashCount/Views/QuickEntry/QuickEntryView.swift`

- Fast transaction creation UI.
- Uses `@Query` for active categories and the default ledger.
- Amount is typed through a custom number pad.
- Supports income/expense toggle, category, note, and date.
- New entries are assigned to the default `生活` ledger when present.
- Saves with `safeSave`.

### Ledger

Files:

- `FlashCount/Views/Ledger/LedgerView.swift`
- `FlashCount/Views/Ledger/EditTransactionView.swift`
- `FlashCount/Views/Ledger/CalendarView.swift`

Capabilities:

- Search by note/category/amount.
- Date filters: all, today, this week, this month, custom.
- Monthly income/expense/net summary.
- List and calendar modes.
- Transaction edit/delete via tap, context menu, and swipe actions.
- Bell button opens `ReminderView`.
- No visible ledger picker or ledger manager in the main flow.

### Budget

Files:

- `FlashCount/Views/Budget/BudgetView.swift`
- `FlashCount/Views/Budget/BudgetComponents.swift`

Capabilities:

- Set current month overall monthly budget.
- Show projected spend and alert cards.
- `AddBudgetView` updates an existing current-month budget when possible instead of always inserting duplicates.

### Reports

File: `FlashCount/Views/Report/ReportView.swift`

Capabilities:

- Weekly/monthly switch.
- Streak card.
- Summary card.
- Daily bar chart.
- Category pie chart.
- Top 5 category ranking.
- Generated insights.

Uses Swift Charts.

### Assets

Files:

- `FlashCount/Views/Asset/AssetDashboardView.swift`
- `FlashCount/Views/Asset/AddAssetView.swift`
- `FlashCount/Views/Asset/PhysicalAssetView.swift`

Capabilities:

- Financial asset and liability dashboard.
- Net worth card with hide/show balance toggle stored in `@AppStorage("hideAssetBalance")`.
- Asset composition chart.
- Add/edit/delete financial accounts.
- Physical asset tracker with depreciation and daily-cost metrics.
- Explicit physical asset sale flow using `soldPrice` and `soldDate`.
- Asset help/tutorial button lives in the asset navigation toolbar, not as a tiny tab overlay.

### Settings

File: `FlashCount/Views/Settings/SettingsView.swift`

Capabilities:

- Appearance picker stored in `@AppStorage("appearance")`.
- Tutorial entry.
- Reminder management entry.
- Recurring rules management entry.
- JSON export/import using `DataBackupService`.
- Data repair using `DataRepairService`.
- About section.

Appearance picker is now wired through `AppearancePreference`; light mode is the default.

### Reminders

Files:

- `FlashCount/Views/Reminder/ReminderView.swift`
- `FlashCount/Services/ReminderStore.swift`
- `FlashCount/Services/ReminderNotificationService.swift`
- `FlashCount/Models/ReminderItem.swift`

Capabilities:

- Create one-time future reminders with date and time.
- Normal reminders schedule one notification.
- Strong reminders schedule multiple notifications after the due time.
- Reminders are stored as JSON in the app documents directory, not SwiftData.
- Users can mark reminders complete or delete them via swipe actions.

Caveat:

- iOS does not let a normal third-party app behave exactly like the system Clock alarm. Strong reminders approximate this with repeated local notifications; critical/continuous alarm-style alerts require Apple-granted entitlements that this self-installed app should not assume.

### Recurring Rules

Files:

- `FlashCount/Views/Recurring/RecurringRulesView.swift`
- `FlashCount/Views/Recurring/AddRecurringRuleView.swift`

Capabilities:

- List recurring rules.
- Add recurring bill rule.
- Pause/resume a rule.

Caveats:

- No edit/delete UI for recurring rules at scan time.
- `AddRecurringRuleView` has an `isExpense` state but no visible income/expense toggle; new rules are effectively expenses unless this changes.

### Onboarding And Tutorial

File: `FlashCount/Views/Onboarding/OnboardingView.swift`

- First-launch onboarding.
- Tutorial explains home widget, lock-screen widget, Back Tap, Siri, and Shortcuts workflows.

### App Intents And Widget

Files:

- `FlashCount/Intents/QuickAddIntent.swift`
- `FlashCountWidget/FlashCountWidget.swift`

Observed behavior:

- `QuickAddExpenseIntent` opens the app via `openAppWhenRun = true`.
- Intent comments say MainTabView will handle showing quick entry, but no bridge/deep-link handling was observed.
- Widget source defines static WidgetKit views, but no project target currently includes it.

## Product And Privacy Assumptions

The README positions the app as:

- Local-only storage.
- No cloud sync.
- No network requests.
- No ads or tracking.
- Open source.

Preserve these assumptions unless the user explicitly asks for cloud/network features.

## Coding Conventions To Preserve

- Prefer SwiftUI views with local `@State`, `@Query`, and `@Environment(\.modelContext)`.
- Use `Decimal` for money.
- Store transaction amounts as positive values and derive sign through `isExpense`.
- Use SF Symbols names for icons.
- Use hex colors plus `Color(hex:)`.
- Follow the current light, semantic-card visual language.
- Prefer `project.yml` edits over manual `.xcodeproj` edits.
- Before schema/model changes, consider SwiftData migration and JSON backup compatibility.
- Before modifying existing files, run `git status --short` and inspect user changes.

## Verification Notes

Latest verification:

- `xcodegen generate` completed.
- `xcrun swiftc -typecheck ...` completed successfully outside the sandbox, required because SwiftData macros need the Swift plugin server.
- `git diff --check` completed.
- `xcodebuild -list -project FlashCount.xcodeproj` completed and reported target/scheme `FlashCount`.
- Full `xcodebuild ... build` reached the project but failed in asset catalog compilation due local CoreSimulator/actool environment errors: `No available simulator runtimes for platform iphonesimulator`.

Known verification gaps:

- No automated tests exist.
- Widget target is not wired, so Widget source is not covered by the current project target.
- Recurring-rule processing needs manual or test verification after startup-flow changes.
- Backup import/export should be tested with duplicate categories, duplicate ledgers, missing ledger IDs, and existing transaction IDs.
- Reminder notifications need device testing because local notification delivery depends on iOS notification settings and Focus modes.

## Suggested High-Value Next Improvements

If asked to improve the project further, good next candidates are:

1. Connect App Intent / Widget / deep link behavior so shortcuts open quick entry directly.
2. Add the Widget Extension target to `project.yml` or remove stale Widget references if not planned.
3. Add unit tests for `BudgetAnalyzer`, `BudgetReminderService`, `RecurringFrequency.nextDate`, physical asset sale math, and backup import de-duplication.
4. Add full custom category management.
5. Add edit/delete support for recurring rules.
6. Add optional reminder repeat rules or snooze actions if reminders become a core workflow.
