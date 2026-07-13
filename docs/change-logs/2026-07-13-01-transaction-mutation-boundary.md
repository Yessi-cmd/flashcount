# Transaction mutation boundary

## Purpose

Move user-driven transaction writes out of SwiftUI views and enforce one persistence boundary for each transaction and its cash-pool projection.

## Affected files

- `FlashCount/Services/FinanceServices/TransactionMutationService.swift`
- `FlashCount/Services/FinanceServices/CashPoolService.swift`
- `FlashCount/Services/FinanceServices/RecurringService.swift`
- `FlashCount/Services/DataServices/CSVTransactionService.swift`
- `FlashCount/Services/DataServices/DataBackupService.swift`
- `FlashCount/Views/QuickEntry/QuickEntryView.swift`
- `FlashCount/Views/Ledger/EditTransactionView.swift`
- `FlashCount/Views/Ledger/LedgerView.swift`
- `FlashCount/Views/Ledger/LedgerComponents.swift`
- `FlashCount/Views/Asset/CashPoolView.swift`
- `FlashCountTests/TransactionMutationServiceTests.swift`
- Generated `FlashCount.xcodeproj/project.pbxproj`

## Behaviour changes

- Quick entry, transaction editing, single deletion, batch deletion, and deletion undo now use one application service instead of mutating SwiftData and cash-pool state independently in each view.
- A mutation validates positive `Decimal` amounts, updates transaction and cash-pool state, performs one SwiftData save, and rolls the context back if any read or write fails.
- Cash-pool state fetch failures are propagated through transaction, recurring, CSV import, backup import, and calibration paths instead of being treated as an empty state.
- Undo restores the deleted transaction's original UUID and creation date as well as its financial and relationship state.
- Duplicate transaction references in a batch deletion are applied only once.

## Verification performed

- Regenerated `FlashCount.xcodeproj` with XcodeGen.
- Ran all 40 unit tests successfully, including four new in-memory SwiftData tests for create/update consistency, delete/restore identity, batch deletion, and invalid amounts.
- Built the app successfully for Debug and Release iOS Simulator configurations.
- Ran four UI smoke tests: onboarding, quick-entry navigation, and immediate category selection passed. The pre-existing uncommitted category-wheel outside-tap cancellation test failed and failed again when run alone; it does not reach a transaction mutation path.
- `git diff --check` passed.

## Remaining limitations

- Recurring generation and import services retain their specialized batch orchestration rather than delegating each transaction to the user-mutation service; their cash-pool errors now propagate and roll back through their existing transaction boundaries.
- The app remains a single Xcode target, so service/view dependency direction is enforced by structure and review rather than module visibility.
- `FlashCountUITests/FlashCountSmokeTests.testQuickEntryCategoryWheelOpensAndCancelsWithoutChangingTheForm` remains failing in the existing category-wheel work and was left unchanged to preserve that user-owned batch.
