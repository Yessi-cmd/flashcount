# Unified privacy visibility

## Purpose

Replace the separate ledger-income and asset-balance visibility states with one authenticated session state, prevent accidental Face ID prompts when opening Assets, and make protected income presentation consistent across the app.

## Affected files

- `FlashCount/Services/SystemServices/PrivacyLockService.swift`
- `FlashCount/FlashCountApp.swift`
- `FlashCount/Views/MainTabView.swift`
- `FlashCount/Views/Ledger/LedgerView.swift`
- `FlashCount/Views/Ledger/CalendarView.swift`
- `FlashCount/Views/Report/ReportView.swift`
- `FlashCount/Views/Recurring/RecurringRulesView.swift`
- `FlashCount/Views/Settings/SettingsView.swift`
- `FlashCount/Views/Asset/AssetDashboardView.swift`
- `FlashCount/Views/Asset/CashPoolView.swift`
- `FlashCount/Views/Asset/PhysicalAssetView.swift`
- `FlashCount/Views/Asset/SavingsGoalView.swift`
- `FlashCount/Views/Asset/InstallmentBillView.swift`
- `FlashCountTests/FinanceDomainTests.swift`
- `project.yml`
- `FlashCount.xcodeproj/project.pbxproj` (regenerated with XcodeGen)

## Behaviour changes

- All income amounts and all asset amounts now follow one in-memory authenticated visibility state. Expenses remain visible while locked.
- Protected income metadata, such as salary category and note content, remains hidden while locked; its amount no longer behaves differently from other income amounts.
- Opening the Assets tab never starts authentication. Entering Assets from the tab bar first locks sensitive content, even if another screen was previously unlocked.
- Tapping a visibility control first shows a confirmation dialog explaining the scope and relock behaviour. Face ID, Touch ID, or device-passcode authentication starts only after explicit confirmation.
- Tapping the visible eye immediately locks all sensitive content. Moving the app to the background also locks it.
- Inactive and app-switcher snapshots are covered by a neutral privacy shield instead of retaining the last visible financial screen.
- Ledger rows, recurring-income rows, and existing asset records cannot open an amount-bearing editor while locked; they route through the same confirmation flow.
- Asset composition, value-based ordering, and financial progress indicators no longer expose proportions while locked. Report status labels and colours no longer reveal whether a masked net result is positive or negative.
- Settings now contains a Privacy section that reports and controls the same global visibility state.

## Verification performed

- Regenerated `FlashCount.xcodeproj` with `xcodegen generate`.
- Built the iOS simulator app with `xcodebuild`; build succeeded.
- Ran the complete `FlashCountTests` suite on an iPhone 17 Pro simulator: 14 tests passed with 0 failures.
- Added regression coverage for unified income/asset policy, protected metadata masking, and confirmation-before-authentication behaviour.
- Ran `git diff --check`; no whitespace errors were reported.

## Remaining limitations

- Simulator tests cover privacy state transitions and policy decisions, but real Face ID/Touch ID presentation and cancellation still require a manual check on physical hardware.
- Privacy visibility is intentionally session-only and is never persisted; relaunching or backgrounding the app starts hidden.
