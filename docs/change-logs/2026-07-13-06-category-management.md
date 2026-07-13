# Complete category management

## Purpose

Allow users to customize the category system without losing historical references or having renamed defaults re-created at startup.

## Affected files

- `FlashCount/Models/Category.swift`
- `FlashCount/Services/DataServices/CategoryManagementService.swift`
- `FlashCount/Services/DataServices/DataBackupService.swift`
- `FlashCount/Services/DataServices/DefaultDataService.swift`
- `FlashCount/Views/Settings/CategoryManagementView.swift`
- `FlashCount/Views/Settings/SettingsView.swift`
- `FlashCountTests/CategoryManagementServiceTests.swift`
- `FlashCountTests/FinanceDomainTests.swift`

## Behaviour changes

- Users can create and edit expense or income categories, choose an SF Symbol and color, and place a category at the top level or under another top-level category.
- Categories can be reordered, archived with their children, restored, or merged into another compatible category.
- Merging migrates transactions, recurring rules, category budgets, and templates in one SwiftData save. Matching category-budget limits are added together.
- Default categories receive stable identifiers and explicit optional hierarchy metadata, so renaming a default does not cause it to be re-seeded.
- Backup version 1.8.0 preserves hierarchy, stable default identifiers, and merge aliases while remaining able to import older supported backups.

## Verification performed

- Added in-memory SwiftData tests for root renaming, child and template updates, reference migration, Decimal budget consolidation, archive/restore cascading, last-root protection, and backup round trips.
- `xcodegen generate` completed successfully and regenerated the Xcode project from `project.yml`.
- An unsigned Debug build for the generic iOS Simulator destination succeeded, including embedded-widget validation.
- All 59 unit tests passed on an iPhone 17 Pro simulator running iOS 26.2.
- All 4 UI smoke tests passed on the same simulator.
- `git diff --check` completed without whitespace errors; the generated project lists the app, unit-test, UI-test, and Widget targets.

## Remaining limitations

- Category hierarchy is intentionally limited to two levels because the quick-entry wheel is designed around one parent ring and its children.
- Merged aliases remain archived to keep default-seeding and backup identity stable; they cannot be restored directly.
