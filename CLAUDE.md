# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
xcodegen generate          # Generate .xcodeproj from project.yml
open FlashCount.xcodeproj  # Open in Xcode, then Cmd+R to run
```

Target: `FlashCount` (scheme `FlashCount`). Configs: `Debug`, `Release`. No test targets exist.

Never hand-edit `FlashCount.xcodeproj/` — edit `project.yml` instead, then regenerate.

## Packaging for AltStore

When asked to **打包** (package), produce an AltStore-compatible `.ipa` in `build/`:

```bash
# 1. Archive
xcodebuild archive \
  -project FlashCount.xcodeproj \
  -scheme FlashCount \
  -configuration Release \
  -archivePath build/FlashCount.xcarchive

# 2. Export IPA
xcodebuild -exportArchive \
  -archivePath build/FlashCount.xcarchive \
  -exportPath build/ \
  -exportOptionsPlist build/ExportOptions.plist

# Result: build/FlashCount.ipa — sideload via AltStore on iPhone
```

- ExportOptions.plist uses `method: development` (free Apple dev account compatible).
- The `.ipa` file lands at `build/FlashCount.ipa`. Copy it to phone or share directly.
- `build/` is in `.gitignore` — artifacts never committed.

## Architecture Overview

**Local-first iOS bookkeeping app** — SwiftUI + SwiftData + Swift Charts. No network, no cloud, no tracking. iOS 17.0+, Swift 5.9.

```
FlashCountApp.swift          → @main entry, WindowGroup, ModelContainer
  └── AppRootView            → PrivacyLockService injection, DefaultDataService startup
        └── MainTabView      → 4 tabs: 账本 / 预算 / [+] / 报表 / 资产
```

**Persistence:** SwiftData `ModelContainer` with 11 models. See `FlashCountApp.swift:10-22` for the list. `ReminderItem` is the exception — stored as JSON in app documents directory to avoid schema migration risk.

## Critical Money Conventions

- **Amounts are ALWAYS stored positive** as `Decimal`. Sign is derived from `Transaction.isExpense`.
- `Transaction.signedAmount` returns negative for expenses, positive for income.
- Use `Decimal` for all money math — never `Double` or `Float`.
- `Decimal.formattedCurrency` for display (`¥1,234.56`), `Decimal.formattedAmount` for raw numbers.
- `DataBackupService` converts `Decimal → Double` for JSON export — be aware of precision implications.

## Key Patterns

### Saving data
```swift
// Preferred: use safeSave() which returns a localized error or nil
if let error = safeSave(modelContext) { /* show alert */ }

// Avoid bare try? — it silently discards save failures
// try? modelContext.save()  ← DON'T use for user-initiated saves
```

### Model mutations and rollback risk
When mutating model properties before `save()`, ensure the mutations are rolled back on failure. The recent `RecurringService` fix illustrates the pattern: save inside the loop after each rule, not once at the end. If you mutate in-memory state (like advancing `nextDueDate`) and the save fails, the in-memory state is out of sync with the store.

### One-time startup guards
Use `private static var didPrepareData = false` (process-lifetime singleton) instead of `@State` for one-time initialization that must survive SwiftUI scene recreation.

### Design System
```swift
DesignSystem.surfaceBackground   // main background
DesignSystem.textPrimary/.textSecondary/.textTertiary
DesignSystem.primaryGradient / .incomeGradient / .expenseGradient
.glassCard()                     // View modifier for card style
Color(hex: "#4EA8F8")           // Hex color support
```

Light mode is the default. Appearance is stored in `@AppStorage("appearance")`.

### Privacy Lock
`PrivacyLockService` is an `ObservableObject` injected via `.environmentObject()` at `AppRootView`. All views that display sensitive amounts (salary income, cash pool, savings goals, installment bills) must guard with `privacyLock.isUnlocked`. The lock engages on `scenePhase != .active`.

## Model Relationships

- `Transaction` → optional `Category`, `Ledger`, `RecurringRule`
- `RecurringRule` → optional `Category`, `Ledger`
- `Budget` → optional `Ledger`, optional `categoryId` (nil = ledger-level budget)
- `Category.deleteRule` = `.nullify` for transaction/recurring rule relationships
- `Ledger.deleteRule` = `.cascade` for transactions and budgets, `.nullify` for recurring rules

## Services (non-UI)

| Service | Role |
|---------|------|
| `RecurringService` | Generates due transactions on startup; called by `DefaultDataService` |
| `BudgetAnalyzer` | Pure calculation — daily allowance, projections, alert level |
| `BudgetReminderService` | Wires budget + PayCycleService + BudgetAnalyzer into view models |
| `PayCycleService` | Computes pay-cycle date ranges from a payday (day of month) |
| `CashPoolService` | Manages `CashPoolState.transactionDelta` aggregation |
| `ReportService` | Weekly/monthly report data including streak calculation |
| `DataBackupService` | Full JSON export/import with DTOs; schema version `1.2.0` |
| `DefaultDataService` | Non-destructive startup seeding of default ledgers/categories |
| `ReminderStore` | JSON file persistence for `ReminderItem` (not SwiftData) |
| `PrivacyLockService` | Face ID / device passcode gate for sensitive financial data |

## Caveats

- `FlashCountWidget/` exists but is NOT wired into `project.yml` or the Xcode project.
- The app is effectively single-ledger now — `selectedLedger` filtering was removed from `LedgerView`. Existing multi-ledger users have transactions interleaved.
- `AddRecurringRuleView` has no visible income/expense toggle; new rules default to expense.
- `BudgetScope.includesInDailyBudget` controls which categories count toward daily budgets (餐饮/出行/购物 only, minus 数码配件/家具家电/大件消费).
- `safeSave()` exists in `ErrorHandling.swift` — prefer it over raw `try? modelContext.save()`.
