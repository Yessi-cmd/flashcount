# Query and view architecture

## Purpose

Avoid loading the complete transaction history on common screens and reduce the responsibilities of the largest SwiftUI source files.

## Affected files

- Ledger and report query paths.
- Ledger and quick-entry feature components.
- XcodeGen test-target configuration and UI smoke tests.

## Behaviour changes

- The normal ledger query is bounded to recent history; older transactions are fetched only for all-history or older custom ranges.
- Report streak calculation reads transactions in bounded pages and stops at the first date gap.
- Ledger row/filter components and quick-entry controls are isolated from their screen coordinators while preserving their public entry points and appearance.
- A UI-test target covers onboarding and quick-entry navigation without adding a Widget target.

## Verification performed

- Regenerated `FlashCount.xcodeproj` with XcodeGen.
- Ran 25 unit tests and 2 UI smoke tests successfully.
- Debug and Release build verification and `git diff --check` are part of final PR validation.

## Remaining limitations

- All-history summaries necessarily read the selected historical range because SwiftData does not provide a portable Decimal aggregate query.
- Debug visual-exploration screens retain their direction-specific private component structure to preserve snapshot tooling.
