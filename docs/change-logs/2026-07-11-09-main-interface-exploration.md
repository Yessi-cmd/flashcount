# Main Interface Visual Exploration

## Purpose

Correct the budget exploration actions and add three directly comparable main-interface directions that retain the bottom tab bar.

## Affected files

- `FlashCount/FlashCountApp.swift`
- `FlashCount/Views/VisualExploration/VisualDirectionExplorationView.swift`
- `FlashCount/Views/VisualExploration/MainInterfaceExplorationView.swift`
- `FlashCount.xcodeproj/project.pbxproj` (regenerated with XcodeGen)
- `docs/visual-direction-exploration.md`
- `docs/visual-direction-screenshots/`
- `docs/main-interface-visual-exploration.md`
- `docs/main-interface-screenshots/`

## Behaviour changes

- Replaced the budget exploration actions with context-appropriate “调整预算” and “查看明细” actions.
- Added a Debug-only main-interface exploration route activated by `-visualHomeExploration`.
- Added restrained, soft, and precise main-interface treatments using identical fixed data and functionality.
- Preserved a five-item bottom tab bar in all three directions and positioned “记一笔” as its central global shortcut.
- Kept all exploration interactions isolated from SwiftData and production navigation.

## Verification performed

- Regenerated the Xcode project with XcodeGen 2.44.1.
- Built the Debug app successfully for iPhone 17 Pro / iOS 26.2 Simulator.
- Launched and captured all three main-interface directions with identical device, content, appearance, and status-bar state.
- Re-captured all three budget directions after correcting their action labels.
- Visually confirmed that content and bottom navigation are fully visible without clipping.
- Ran all 8 existing `FinanceDomainTests`; all passed with zero failures.

## Remaining limitations

- Main-interface exploration uses fixed sample data and demo-only actions.
- Only light appearance, default text size, and iPhone 17 Pro were visually verified.
- No direction has been selected or applied to the production ledger, budget page, or tab bar.
