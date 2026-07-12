# Visual Direction Exploration

## Purpose

Create three directly comparable visual directions for one representative FlashCount budget page without changing existing business logic or rolling a direction out across the app.

## Affected files

- `FlashCount/FlashCountApp.swift`
- `FlashCount/Views/VisualExploration/VisualDirectionExplorationView.swift`
- `FlashCount.xcodeproj/project.pbxproj` (regenerated with XcodeGen)
- `docs/visual-direction-exploration.md`
- `docs/visual-direction-screenshots/direction-a.png`
- `docs/visual-direction-screenshots/direction-b.png`
- `docs/visual-direction-screenshots/direction-c.png`
- `docs/visual-direction-screenshots/visual-directions-comparison.png`

## Behaviour changes

- Added a Debug-only visual exploration root activated by `-visualDirectionExploration`.
- Added three switchable treatments of the same fixed “current budget” content: restrained, soft, and precise.
- Added `-visualDirectionA`, `-visualDirectionB`, and `-visualDirectionC` launch arguments for deterministic selection.
- Added `-visualDirectionSnapshot` to hide the exploration switcher for clean screenshots.
- Exploration actions show explicit demo feedback and never read or write persisted finance data.
- Normal Debug launches without the exploration argument and all Release launches retain the existing app root and behaviour.

## Verification performed

- Regenerated `FlashCount.xcodeproj` using XcodeGen 2.44.1.
- Built the FlashCount Debug app successfully with Xcode 26.2 for iPhone 17 Pro / iOS 26.2 Simulator.
- Ran all 8 existing `FinanceDomainTests`; all passed with zero failures.
- Launched all three directions independently with deterministic arguments.
- Captured and visually inspected all three simulator screenshots at identical device size, data, light appearance, and status-bar state.
- Confirmed the full hierarchy, three transaction rows, status, and both actions are visible without clipping in each direction.

## Remaining limitations

- Exploration is intentionally isolated and is not connected to live budget or transaction data.
- Only light appearance, default text size, and iPhone 17 Pro were visually verified in this batch.
- No direction has been selected or propagated to production pages.
