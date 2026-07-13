# Category budgets

## Purpose

Add independent spending limits for top-level expense categories while preserving the existing overall daily-budget workflow.

## Affected files

- `FlashCount/Services/BudgetServices/CategoryBudgetService.swift`
- `FlashCount/Views/Budget/BudgetView.swift`
- `FlashCount/Views/Budget/CategoryBudgetsView.swift`
- `FlashCount/Views/QuickEntry/QuickEntryView.swift`
- `FlashCountTests/FinanceDomainTests.swift`

## Behaviour changes

- Users can add, adjust, and delete category budgets for the current pay cycle.
- A top-level category budget includes spending from all of its child categories and excludes other groups and other cycles.
- The budget tab summarizes up to three category-budget progress bars and highlights categories needing attention.
- Quick entry surfaces a category-specific warning after save before falling back to the overall daily-budget warning.
- Duplicate budgets for the same category and cycle are consolidated during an edit.

## Verification performed

- Added unit coverage for child-category aggregation, period exclusion, unrelated-category exclusion, and newest-duplicate selection.
- `xcodegen generate` completed successfully and regenerated the Xcode project from `project.yml`.
- An unsigned Debug build for the generic iOS Simulator destination succeeded, including embedded-widget validation.
- All 59 unit tests passed on an iPhone 17 Pro simulator running iOS 26.2.
- All 4 UI smoke tests passed on the same simulator.
- `git diff --check` completed without whitespace errors; the generated project lists the app, unit-test, UI-test, and Widget targets.

## Remaining limitations

- Category budgets are intentionally scoped to top-level expense categories to avoid overlapping limits between a group and its children.
- Budgets are set per pay cycle; there is no automatic carry-over to a future cycle.
