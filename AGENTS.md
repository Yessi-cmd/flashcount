# FlashCount Agent Instructions

Single source of truth for AI coding agents working in this repository. `CLAUDE.md` imports this file. Keep this document in sync with reality: any structural change (adding/removing targets, migrating storage, adding/removing models, changing the schema version) must update this file in the same batch.

## Architecture Overview

**Local-first iOS bookkeeping app** — SwiftUI + SwiftData + Swift Charts. No network, no cloud, no tracking (there is no `URLSession` anywhere in the codebase; keep it that way). iOS 17.0+, Swift 5.9.

```
FlashCountApp.swift          → @main entry, WindowGroup, versioned ModelContainer
  └── AppRootView            → PrivacyLockService injection, DefaultDataService startup
        └── MainTabView      → 5 tabs: 账本 / 预算 / [+] / 报表 / 资产
```

**Persistence:** SwiftData with a versioned schema — `Schema(versionedSchema: FlashCountSchemaV2.self)` plus `FlashCountMigrationPlan` (see `FlashCount/Core/FlashCountSchema.swift`). SchemaV2 has 14 models: Transaction, Category, Ledger, RecurringRule, RecurringOccurrence, Budget, Asset, PhysicalAsset, CashPoolItem, CashPoolState, SavingsGoal, InstallmentBill, TransactionTemplate, Reminder. Reminders were migrated from a legacy JSON file into SwiftData; `FileReminderStore` (in `Services/DataServices/ReminderStore.swift`) is a read-only legacy codec kept for one-time import, alongside the live `ReminderDataService`.

## Build & Run

```bash
xcodegen generate          # Generate .xcodeproj from project.yml
open FlashCount.xcodeproj  # Open in Xcode, then Cmd+R to run

# Run tests on a simulator
xcodebuild test -project FlashCount.xcodeproj -scheme FlashCount \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

Targets: `FlashCount` (app), `FlashCountWidget` (embedded extension), `FlashCountTests` (unit), `FlashCountUITests` (UI smoke). Configs: `Debug`, `Release`. GitHub Actions (`.github/workflows/ios-ci.yml`) regenerates the project and runs the full test suite on an iOS simulator for pushes and PRs to `main`.

Never hand-edit `FlashCount.xcodeproj/` — edit `project.yml`, then regenerate with XcodeGen.

## Critical Money Conventions

- Amounts are ALWAYS stored positive as `Decimal`. Sign is derived from `Transaction.isExpense`; `Transaction.signedAmount` returns negative for expenses.
- Use `Decimal` for all money math — never `Double` or `Float`. Make changes to related persisted data atomically where possible.
- `Decimal.formattedCurrency` for display (`¥1,234.56`), `Decimal.formattedAmount` for raw numbers.
- Backups encode money as strings via `CodableMoney` (exact round-trip), while still decoding legacy `Double` values from old backups. Current backup schema version: `1.9.0` (minimum supported `1.0.0`), defined in `DataBackupService`.

## Key Patterns

### Saving data
```swift
// Preferred: safeSave() (Core/ErrorHandling.swift) returns a localized error or nil
if let error = safeSave(modelContext) { /* show alert */ }
// Never use bare `try? modelContext.save()` for user-initiated saves.
```

### Model mutations and rollback risk
When mutating model properties before `save()`, ensure mutations are rolled back on failure. `RecurringService` saves inside the loop after each rule rather than once at the end — if in-memory state (like an advanced `nextDueDate`) survives a failed save, it is out of sync with the store.

### One-time startup guards
Use `private static var didPrepareData = false` (process-lifetime singleton) instead of `@State` for one-time initialization that must survive SwiftUI scene recreation.

### Design System
```swift
DesignSystem.surfaceBackground   // main background
DesignSystem.textPrimary/.textSecondary/.textTertiary
DesignSystem.primaryGradient / .incomeGradient / .expenseGradient
.glassCard()                     // View modifier for card style
Color(hex: "#4EA8F8")            // Hex color support
```
Light mode is the default; appearance preference lives in `@AppStorage("appearance")`.

### Privacy Lock
`PrivacyLockService` is an `ObservableObject` injected via `.environmentObject()` at `AppRootView`. Views that display sensitive amounts (salary income, cash pool, savings goals, installment bills) must guard with `privacyLock.isUnlocked`. The lock engages when `scenePhase != .active`.

## Model Relationships

- `Transaction` → optional `Category`, `Ledger`, `RecurringRule`
- `Category.deleteRule` = `.nullify` for transaction and recurring-rule relationships
- `Ledger.deleteRule` = `.cascade` for transactions and budgets, `.nullify` for recurring rules — deleting a `Ledger` destroys its transactions. The app is single-ledger by design; the only legitimate `delete(ledger)` call site is the consolidation path in `DefaultDataService`, which must verify the ledger is empty first. Never add UI that deletes ledgers.
- `Budget` → optional `Ledger`, optional `categoryId` (nil = ledger-level budget)

## Services (non-UI)

Grouped under `FlashCount/Services/`:

| Service | Role |
|---------|------|
| `RecurringService` | Generates due transactions on startup; called by `DefaultDataService` |
| `BudgetAnalyzer` | Pure calculation — daily allowance, projections, alert level |
| `BudgetReminderService` | Wires budget + `PayCycleService` + `BudgetAnalyzer` into view models |
| `PayCycleService` | Computes pay-cycle date ranges from a payday (day of month) |
| `CashPoolService` | Manages `CashPoolState.transactionDelta` aggregation |
| `ReportService` / `ReportAnalytics` / `ReportPeriodCalculator` | Report data, insights, streaks, period windows |
| `DataBackupService` | Full JSON export/import with DTOs; `CodableMoney` amounts |
| `CSVTransactionService` | CSV import/export of transactions |
| `DataHealthService` | Local data health checks and repair plans |
| `LocalActionCenterService` | Aggregates due/overdue/suggested actions |
| `CashFlowForecastService` | Cash flow projection |
| `DefaultDataService` | Non-destructive startup seeding + single-ledger consolidation |
| `ReminderDataService` | SwiftData persistence for reminders (legacy JSON import via `FileReminderStore`) |
| `NotificationScheduleCoordinator` / `ReminderNotificationService` | Local notification scheduling |
| `PrivacyLockService` | Face ID / device passcode gate for sensitive amounts |
| `TransactionMutationService` / `LedgerQueryService` | Transaction writes with undo snapshots; ledger queries |

## Caveats

- The app is single-ledger by design. The `Ledger` model remains for schema stability; existing multi-ledger users had their data consolidated. See Model Relationships for the cascade-delete hazard.
- `BudgetScope.includesInDailyBudget` controls which categories count toward daily budgets (餐饮/出行/购物 only, minus 数码配件/家具家电/大件消费).
- `Views/VisualExploration/` is a DEBUG-only design lab reached via launch arguments; it never runs in Release.

## Project Rules

- Use `main` as the default and only persistent branch. Commit routine work directly to `main`. Create a temporary branch only when isolation is genuinely needed; merge it back promptly, then delete both local and remote copies.
- Edit `project.yml`, not `project.pbxproj`; regenerate with XcodeGen afterward.
- Preserve the local-first privacy model. Do not add network dependencies unless explicitly requested.

## Documentation Rules

- This file is the only agent-guidance document. Do not create parallel context files (`docs/agent.md` and `docs/AI_PROJECT_CONTEXT.md` were removed for drifting out of date).
- Significant architecture decisions get a dated record in `docs/decisions/` (lightweight ADR: context → decision → consequences).
- The former per-batch change-log requirement is retired; `docs/change-logs/` is a frozen historical archive. Git history is the changelog — write informative commit messages instead.

## IPA Packaging Rules（打包）

When asked to **打包** (package), produce an AltStore-compatible `.ipa` in `build/`:

- Build AltStore packages with `scripts/package-altstore.sh`. They must contain only the unsigned main app, with no code signature or provisioning profile.
- Keep IPA outputs in `build/` (gitignored) using only the canonical names `FlashCount.ipa` and `FlashCount-AltStore.ipa`. Never add version numbers, dates, or suffix copies to IPA filenames; a rebuild replaces the canonical file only after verification succeeds. Keep at most one IPA per distribution channel.
- Never publish a development-signed IPA. Inspect an IPA for embedded provisioning profiles and personal/device identifiers before any external upload.
- Follow the full packaging and verification policy in `docs/packaging.md`.
