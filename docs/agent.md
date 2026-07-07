# FlashCount Agent Guide

Last analyzed: 2026-07-05

This file is for coding agents working in this repository. It summarizes the project shape, durable conventions, and places where careless changes are likely to hurt the app.

## Project Snapshot

FlashCount is a local-first iOS bookkeeping app written in SwiftUI. The product promise in `README.md` is: data stays on device, no cloud sync, no ads, no tracking, and no network dependency.

Core stack:

- SwiftUI for UI.
- SwiftData for local persistence.
- Swift Charts for reports and asset charts.
- App Intents for Siri / Shortcuts entry points.
- UserNotifications for local reminders.
- XcodeGen with `project.yml` as the source of truth for the Xcode project.

Declared requirements:

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9

## Repository Map

- `README.md`: product overview and setup.
- `project.yml`: canonical XcodeGen project config. Prefer editing this over hand-editing `FlashCount.xcodeproj`.
- `FlashCount/`: main app source.
- `FlashCount/FlashCountApp.swift`: app entry, SwiftData container, startup preparation.
- `FlashCount/Models/`: SwiftData models plus JSON-only reminder model.
- `FlashCount/Services/`: startup data, recurring rules, reminders, budget/report calculations, backup/import.
- `FlashCount/Helpers/`: design system, formatting extensions, save/error/data-repair helpers.
- `FlashCount/Views/`: SwiftUI feature screens.
- `FlashCount/Intents/`: App Intent / Shortcuts definitions.
- `FlashCountWidget/`: WidgetKit source exists, but is not currently wired into `project.yml`.
- `FlashCount.xcodeproj/`: generated project. Regenerate from `project.yml` when project structure changes.
- `dist/` and `build/`: generated artifacts; avoid editing manually.

## Current Build Shape

`xcodebuild -list -project FlashCount.xcodeproj` reports one target and one scheme:

- Target: `FlashCount`
- Scheme: `FlashCount`

`FlashCountWidget/` is present, but there is no Widget Extension target in `project.yml` at the time of this analysis. If work touches widget behavior, first add the extension target to `project.yml` and regenerate the project.

There are no test targets or test files currently.

## Useful Commands

```bash
xcodegen generate
xcodebuild -list -project FlashCount.xcodeproj
xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -destination 'platform=iOS Simulator,name=iPhone 15' build
git diff --check
git status --short
```

Notes:

- Full simulator builds may fail in sandboxed or headless environments if CoreSimulator services are unavailable.
- SwiftData macros may require a real Xcode toolchain and plugin service. If typechecking/building fails with macro/plugin errors, verify outside the sandbox or in Xcode.

## Worktree Discipline

This repository often has in-progress local changes. Before editing:

1. Run `git status --short`.
2. Inspect diffs for any file you plan to touch.
3. Do not revert unrelated user changes.
4. Keep changes scoped; avoid broad formatting churn.

## App Startup And Persistence

`FlashCountApp` creates a SwiftData model container for:

- `Transaction`
- `Category`
- `Ledger`
- `RecurringRule`
- `Budget`
- `Asset`
- `PhysicalAsset`

`ReminderItem` is not in SwiftData. It is Codable JSON stored through `ReminderStore`.

`AppRootView`:

- Applies `AppearancePreference` from `@AppStorage("appearance")`.
- Configures local notification foreground presentation.
- Runs `DefaultDataService(modelContext:).prepareAppData()` once on appear.

`DefaultDataService`:

- Non-destructively inserts missing default ledger/category data.
- Keeps `生活` as the default ledger.
- Removes empty legacy `生意` ledgers only when they have no transactions, budgets, or recurring rules.
- Archives old legacy expense categories.
- Calls `RecurringService.processAllDueRules()` after seeding.

## Navigation

Root UI is `MainTabView` with a custom bottom tab bar:

- `LedgerView`: transaction list, search/filter/calendar, reminders entry, budget reminder card.
- `BudgetView`: current-month budget analysis and monthly limit editing.
- Center plus button: opens `QuickEntryView`, except on asset tab where it opens `AddAssetView`.
- `ReportView`: weekly/monthly charts and insights.
- `AssetDashboardView`: financial accounts plus physical asset tracking.

First launch shows `OnboardingView` and immediately sets `hasCompletedOnboarding = true` when shown.

## Data Model Rules

Money:

- Use `Decimal` for money in app models and calculations.
- Transaction `amount` is always positive.
- Transaction direction is represented by `isExpense`.
- Use `signedAmount` only when a signed value is needed.
- Backup DTOs currently convert `Decimal` to `Double`; be careful if exact decimal round-tripping becomes a requirement.

Categories:

- Categories use SF Symbol names and hex colors.
- Expense and income categories are seeded from grouped definitions in `Category.swift`.
- Parent/child grouping is inferred by category definitions and `sortOrder`; preserve this when adding defaults.
- Archived categories should remain available for old transactions but hidden from normal pickers.

Ledgers:

- The current product flow is effectively single-ledger personal bookkeeping.
- Default ledger is `生活`.
- Multi-ledger support is legacy/partial. Do not assume every screen exposes a ledger picker.

Budgets:

- Monthly budgets are attached to a ledger and can optionally have `categoryId`.
- Current UI primarily uses overall monthly budget where `categoryId == nil`.
- `BudgetReminderService` daily budget scope intentionally includes only daily categories such as food, travel, and ordinary shopping, while excluding rent, subscriptions, health, learning, travel, accounting, large purchases, and digital/home appliance purchases.

Recurring rules:

- `RecurringRule` supports daily, weekly, monthly, yearly.
- Startup processing creates missing transactions while `nextDueDate <= now`.
- Generated transactions link back to the source recurring rule.

Assets:

- `Asset` represents financial accounts.
- Credit cards and loans are liabilities; use `signedBalance` for net worth calculations.
- `PhysicalAsset` tracks purchase price/date, salvage value, target daily cost, sale price/date, archive state, and depreciation/daily-cost metrics.

Reminders:

- `ReminderItem` is Codable, not SwiftData.
- Strong reminders schedule multiple local notifications at offsets `[0, 60, 180, 300, 600]` seconds.
- Local notifications cannot behave like system Clock alarms without special Apple entitlements.

## Important Services

- `DefaultDataService`: startup seed/repair-ish preparation.
- `RecurringService`: creates due recurring transactions and advances due dates.
- `BudgetAnalyzer`: pure budget math; good first target if tests are added.
- `BudgetReminderService`: chooses current budget, scoped monthly spending, and reminder copy.
- `ReportService`: weekly/monthly totals, category breakdown, daily expenses, streak, insights.
- `DataBackupService`: JSON export/import for categories, ledgers, transactions, assets, physical assets, recurring rules, and budgets. Backup version is currently `1.2.0`.
- `ReminderStore`: JSON file persistence for reminders.
- `ReminderNotificationService`: notification authorization, scheduling, cancellation, foreground delegate.
- `DataRepairService`: repairs missing categories, invalid amounts, and missing ledgers.

## UI Conventions

- Use existing `DesignSystem` colors, gradients, corner radii, `glassCard()`, and semantic text colors.
- Use SF Symbols for icons.
- Preserve the light, clean, local-first personal finance feel.
- Prefer local SwiftUI state, `@Query`, and `@Environment(\.modelContext)` patterns already used in views.
- Use `safeSave(_:)` plus `.saveErrorAlert(...)` for user-facing save failures where the surrounding code already follows that pattern.
- Do not introduce network UI, account/login flows, analytics, or cloud sync unless explicitly requested.

## Backup And Migration Caution

Changing any SwiftData `@Model` shape can affect existing local data and backup compatibility. Before changing models:

- Consider SwiftData migration behavior.
- Update `DataBackupService` DTOs/import/export if the field should survive backup.
- Keep import order safe: categories and ledgers first, then models that reference them.
- Preserve import de-duplication by IDs and by category/ledger names where appropriate.
- Test import with duplicate categories, duplicate ledgers, missing ledger IDs, and existing transaction IDs.

## Known Gaps And Risk Areas

- No automated tests exist.
- Widget source exists but is not part of the generated project target.
- `QuickAddExpenseIntent` opens the app, but there is no robust deep-link bridge observed that automatically presents `QuickEntryView`.
- Recurring-rule processing happens at startup and needs manual/device verification.
- Reminder notification delivery depends on iOS notification settings, Focus modes, and device behavior.
- Full simulator builds may be blocked by local CoreSimulator availability.

## Suggested Verification By Change Type

For model/service math:

- Add focused unit tests if a test target is introduced.
- At minimum, exercise the pure functions manually or with a small temporary harness.

For SwiftUI screens:

- Build in Xcode or with `xcodebuild`.
- Manually inspect small-screen layout, sheet flows, and empty states.

For backup/import:

- Export existing data.
- Import into a fresh install or fresh simulator store.
- Verify relationships: transaction category, ledger, recurring rule, assets, physical assets, budgets.

For reminders:

- Test on a real device when possible.
- Check authorization denied, provisional/not determined, foreground notification, completion, and deletion flows.

For project structure:

- Edit `project.yml`.
- Run `xcodegen generate`.
- Re-run `xcodebuild -list -project FlashCount.xcodeproj`.

## High-Value Future Improvements

- Wire App Intent / Shortcut / Widget entry into a real quick-entry presentation path.
- Add the Widget Extension target to `project.yml`.
- Add tests for `BudgetAnalyzer`, `BudgetReminderService`, `RecurringFrequency.nextDate`, physical asset sale math, and backup import de-duplication.
- Add custom category management.
- Add fuller recurring rule edit/delete UI.
- Add optional reminder snooze/repeat if reminders become a core workflow.
