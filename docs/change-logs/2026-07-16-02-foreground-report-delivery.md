# Foreground report delivery

## Purpose

Complete scheduled report delivery so a report arriving while FlashCount is active opens the matching in-app report, while background and terminated delivery continues to use a local notification.

## Affected files

- `FlashCount/Core/ReportRoute.swift`
- `FlashCount/Services/SystemServices/ReminderNotificationService.swift`
- `FlashCount/Views/MainTabView.swift`
- `FlashCount/Views/Report/ReportView.swift`
- `FlashCountTests/AppRoutingTests.swift`
- `FlashCountUITests/FlashCountSmokeTests.swift`

## Behaviour changes

- Report notification routes now distinguish between a normal report-tab destination and a foreground report sheet.
- A report notification delivered while the app is active opens the complete report for the delivered period and timestamp.
- Foreground report delivery keeps the notification in Notification Center and plays its sound, but suppresses the redundant system banner because the in-app report is already visible.
- Normal reminder notifications keep their existing foreground banner, list, and sound behaviour.
- Main-level sheets now use one item-driven destination. If quick entry or another main editor is already presented, an arriving report waits until that sheet is dismissed instead of discarding in-progress input.
- Tapping a notification from the background or after a cold launch still opens the corresponding report tab.

## Verification

- Added routing tests for foreground report presentation and non-report payload rejection.
- Added UI coverage that launches a simulated foreground monthly report, verifies the monthly report is selected, and dismisses back to the original tab.
- Added UI coverage proving a foreground daily report waits for quick entry to close before it is presented.
- Simulator build completed successfully on iOS 26.2.
- All 87 tests passed with no failures or skips.
- Simulator visual inspection confirmed the foreground sheet shows the delivered monthly period, scheduled report range, report content, and a visible close action.

## Remaining limitations

- iOS notification delivery still depends on notification permission, Focus modes, and device settings.
- iOS limits pending local notifications; opening FlashCount continues to refresh the rolling schedule.
