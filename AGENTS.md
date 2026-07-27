# FlashCount Agent Instructions

Single source of truth for AI coding agents working in this repository. `CLAUDE.md` imports this file. Keep this document in sync with reality: any structural change (adding/removing targets, migrating storage, adding/removing models, changing the schema version) must update this file in the same batch.

## Architecture Overview

**Local-first iOS bookkeeping app** — SwiftUI + SwiftData + Swift Charts. No network, no cloud, no tracking (there is no `URLSession` anywhere in the codebase; keep it that way). iOS 17.0+, Swift 5.9.

```
FlashCountApp.swift          → @main entry, WindowGroup, versioned ModelContainer
  └── AppRootView            → PrivacyLockService injection, DefaultDataService startup
        └── MainTabView      → 5 tabs: 账本 / 预算 / [+] / 报表 / 资产
```

**Persistence:** SwiftData with a versioned schema — `Schema(versionedSchema: FlashCountSchemaV3.self)` plus `FlashCountMigrationPlan` (see `FlashCount/Core/FlashCountSchema.swift`). SchemaV3 has 13 models: Transaction, Category, Ledger, RecurringRule, RecurringOccurrence, Budget, PhysicalAsset, CashPoolItem, CashPoolState, SavingsGoal, InstallmentBill, TransactionTemplate, Reminder. The `Asset` account model was removed in July 2026 — the class survives only so SchemaV1/V2 and the V2→V3 conversion stage compile; never use it in new code. Reminders were migrated from a legacy JSON file into SwiftData; `FileReminderStore` (in `Services/DataServices/ReminderStore.swift`) is a read-only legacy codec kept for one-time import, alongside the live `ReminderDataService`.

## Build & Run

```bash
./scripts/generate-project.sh   # Generate .xcodeproj from project.yml
open FlashCount.xcodeproj  # Open in Xcode, then Cmd+R to run

# Run tests on a simulator
xcodebuild test -project FlashCount.xcodeproj -scheme FlashCount \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

Targets: `FlashCount` (app), `FlashCountTests` (unit), `FlashCountUITests` (UI smoke). Configs: `Debug`, `Release`. The former `FlashCountWidget` extension was removed in July 2026 — it only offered deep-link shortcuts and never shipped in AltStore packages; quick entry lives in Siri/Back Tap/Shortcuts instead. GitHub Actions (`.github/workflows/ios-ci.yml`) regenerates the project and runs the full test suite on an iOS simulator for pushes and PRs to `main`.

Never hand-edit `FlashCount.xcodeproj/` — edit `project.yml`, then regenerate with XcodeGen.

Regenerate via `scripts/generate-project.sh`, not bare `xcodegen generate`. `project.yml` includes `project.local.yml` (machine-private Release signing, gitignored), and **XcodeGen's `include` cannot be optional** — `optional: true` is silently ignored and a missing file aborts generation while still exiting 0. That broke every CI run from 2026-07-26 until it was fixed, and it breaks every fresh clone. The script writes a comment-only placeholder when the file is absent.

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

`requestReveal()` goes straight to biometrics. There used to be a confirmation dialog in front of it; it was removed because the user tapped the masked value on purpose — the system auth sheet is the confirmation, and its reason string carries the "visible for this session, hidden again on background" explanation. Do not re-add a pre-auth confirmation step. Switching to the asset tab does **not** re-lock either: backgrounding already locks, so re-locking per tab switch only multiplied the unlock cost by the number of switches. `isUnlocked` must still never be set true without a successful evaluation — `FinanceDomainTests` guards that.

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
| `CashPoolService` | Manages `CashPoolState.transactionDelta` aggregation; `calibrate` realigns it to a real-world balance |
| `AssetPortfolioSnapshot` | The asset tab's whole aggregation, extracted from the view so net worth math is testable |
| `InstallmentRepaymentService` | Advances an installment and writes its expense in one commit |
| `SavingsGoalService` | Deposit / withdraw against a goal, without touching the ledger |
| `AssetBreakdown` | Turns a snapshot into drill-down lines for 可动用资金 / 总资产 / 总负债 |
| `LocalAnalyticsDataStore` → `ReportComputationWorker` → `ReportCalculator` | The only report pipeline: a `@ModelActor` reads value snapshots off the UI context, an actor computes, `ReportCalculator` (in `ReportAnalytics.swift`) aggregates. Report/insight types live in `ReportModels.swift`, period math in `ReportPeriodCalculator.swift`. Tests must exercise this path — a parallel `ReportService` once existed, went dead, and kept the tests pointed at code the app never ran. |
| `ReportStreakCalculator` | Shared streak semantics. The data actor uses it to decide how far back to scan; the calculator uses it to count. Both sides must keep using it, or "how far we scan" and "how far we count" drift apart. Chunked scans are day-aligned — an unaligned boundary splits the seam day and reads as a false gap. |
| `ReportPageCache` | LRU (12) for completed/scheduled reports, keyed by data digest. `.current` targets are deliberately excluded: their reference instant moves constantly and would only thrash the cache. |
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
| `QuickEntryFeedbackCenter` | Post-save feedback channel for quick entry. Injected at `AppRootView` (not `MainTabView` — the DEBUG quick-entry review path bypasses the tab view and would crash without it). Holds the saved transaction by `PersistentIdentifier`, not by object, so undo cannot act on a stale reference; expires itself after `visibleSeconds`. |

## Caveats

- The app is single-ledger by design. The `Ledger` model remains for schema stability; existing multi-ledger users had their data consolidated. See Model Relationships for the cascade-delete hazard.
- `BudgetScope.includesInDailyBudget` controls which categories count toward daily budgets (餐饮/出行/购物 only, minus 数码配件/家具家电/大件消费).
- Net worth has exactly one source of truth: the cash pool (`AssetPortfolioSnapshot`). The old `Asset` account list duplicated it and was summed alongside it, double-counting anything recorded twice. Physical assets and savings goals are deliberately excluded from net worth (illiquid / already sitting in cash) and the card says so on screen.
- Asset figures are drillable (`AssetBreakdownSheet`). The breakdown lines come from `AssetPortfolioSnapshot.breakdown(_:)`, i.e. the same computation as the card, and `AssetBreakdownTests` asserts the item lines always sum to the headline number — a drill-down that disagrees with its total is worse than none. `记账增减` drills a second level into the transactions behind it; it is the one component users could never verify, which is what made 校准 the only recourse.
- Paying an installment must write the matching expense (`InstallmentRepaymentService`). Available funds are `资金净额 + 交易增减 − 分期待还`, so releasing the liability without a ledger entry makes paying down debt look like gaining money. The opt-out exists only for users who already recorded the payment by hand.
- Savings deposits deliberately create no transaction — the money moved from spendable to saved, it did not leave. Booking it would make budgets and reports count saving as spending.
- `PhysicalAsset`'s time-dependent math takes an explicit `asOf:` date so depreciation can be tested. Multiply before dividing in money math; the reverse introduced a repeating-decimal artifact.
- Report figures are drillable: tapping a category or chart bucket opens `ReportDrillDownView`, which filters by `LedgerFilter.categoryRootName` — the same root-category grouping the cards aggregate on, so the drill-down total always reconciles with the number tapped.
- The report's income composition card and the shared image card both hide income entirely while the privacy lock is engaged — for income, the category names (工资, 奖金) are themselves the disclosure, not just the amounts.
- `ReportShareCard` takes every value as a parameter. `ImageRenderer` draws outside the view hierarchy, so any `@EnvironmentObject` it reached for would render blank.
- The report tab only generates while `isActive`. TabView keeps the page alive, so without that guard every ledger save rebuilds the report offscreen.
- Saving a quick entry closes the sheet immediately; confirmation, the post-save budget reminder and **undo** all live in the toast that `MainTabView` overlays (`QuickEntrySavedToast`). There is deliberately no blocking success page and no "再记一笔" button in the toast — the toast floats directly above the tab bar's own 记一笔 button. Do not reintroduce a modal success state: it charged every entry one extra tap at the exact moment the task was already done.
- A category tile has exactly one tap behaviour: select (falling back to the last-used child of that root). The wheel opens from the visible 换小类 button under the grid, or VoiceOver's "选择小类" action. Two cleverer designs were tried and measured as broken — a corner chevron badge (the tile's tappable box is only ~38pt wide, so a 32pt badge sat on its centre and "tapping the middle" opened the wheel) and `simultaneousGesture(LongPressGesture)` (it swallowed plain taps and the tile stopped responding). The comment in `CategorySelectionTile` says so; don't walk back into either.
- The keypad's `收入`/`支出` keys sit next to 6 and 3, so a mis-tap is cheap to make. Switching type remembers each side's own selection (`rememberedExpenseCategory` / `rememberedIncomeCategory`) so a round trip is lossless, and the keypad path gives haptic feedback. The `+` key accumulates into `pendingSum`; `resolvedAmount()` is the only place that decides what gets saved.
- The middle tab-bar button always opens quick entry, on every tab. It used to become an action menu on the asset tab — one button, two behaviours — while 添加资金项 was already in that tab's toolbar.
- `AdaptiveMetricRow` switches on `dynamicTypeSize.isAccessibilitySize`, deliberately **not** `ViewThatFits`. The metric cells carry `maxWidth: .infinity` for equal-width columns, and a flexible candidate answers "fits" for any proposed width, so `ViewThatFits` would always pick the horizontal branch and the adaptation would silently do nothing.
- The ledger's search field and date strip are a pinned section header, so they stay reachable while scrolling the list without moving above the summary card. The action-center badge count is computed in a `.task(id:)` off the render path (it runs `pendingOccurrences`, which replays recurring rules) and feeds on the same inputs as `ActionCenterView` — a badge that says 3 while the sheet lists 4 is worse than no number.
- The report's logging heatmap uses fixed 30pt square cells rather than `.flexible()` columns: filling the card width stretched each day into a ~44×16 bar, which reads as a barcode instead of a calendar. `loggingDays` is Monday-aligned and 35–41 days long, so the grid is 5–6 rows with a possibly short last row.
- `Views/VisualExploration/` is a DEBUG-only design lab reached via launch arguments; it never runs in Release.
- `-uiTestUnlockPrivacy` (DEBUG only) starts `PrivacyLockService` unlocked so UI tests and visual reviews can see privacy-gated screens; biometrics cannot be satisfied in the simulator.

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

- Build AltStore packages with `scripts/package-altstore.sh`. They must contain only the unsigned main app, with no app extensions, code signature, or provisioning profile.
- Keep IPA outputs in `build/` (gitignored) using only the canonical names `FlashCount.ipa` and `FlashCount-AltStore.ipa`. Never add version numbers, dates, or suffix copies to IPA filenames; a rebuild replaces the canonical file only after verification succeeds. Keep at most one IPA per distribution channel.
- Never publish a development-signed IPA. Inspect an IPA for embedded provisioning profiles and personal/device identifiers before any external upload.
- Follow the full packaging and verification policy in `docs/packaging.md`.
