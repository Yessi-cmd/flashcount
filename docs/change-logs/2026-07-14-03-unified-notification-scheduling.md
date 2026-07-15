# Unified notification scheduling

## Purpose

Coordinate reminder-item and report notifications under iOS's pending-request capacity using one deterministic, nearest-trigger-first schedule.

## Affected files

- `FlashCount/FlashCountApp.swift`
- `FlashCount/Services/DataServices/DataBackupService.swift`
- `FlashCount/Services/SystemServices/NotificationScheduleCoordinator.swift`
- `FlashCount/Services/SystemServices/ReminderNotificationService.swift`
- `FlashCount/Services/SystemServices/ReportReminderNotificationService.swift`
- `FlashCount/Views/Reminder/ReminderView.swift`
- `FlashCount/Views/Report/ReportReminderSettingsView.swift`
- `FlashCountTests/NotificationScheduleCoordinatorTests.swift`

## Behaviour changes

- Normal and strong reminder offsets, repeating daily/weekly reports, and rolling monthly/yearly reports are planned together.
- FlashCount reserves space for pending requests it does not manage, then keeps the nearest managed triggers within the remaining 64-request capacity.
- User reminder triggers win exact-time ties over report triggers; identifiers provide deterministic final ordering.
- Monthly and yearly candidates are generated far enough ahead to fill available capacity instead of using fixed 12/3 limits.
- Scheduling is serialized by an actor and rebuilt after reminder or report-setting changes, app activation, startup, and backup restoration.
- Both reminder settings surfaces explain when distant candidates are deferred and distinguish persistence success from system-scheduling failure.

## Verification

- Added coverage for capacity selection, tie-breaking, strong reminder offsets, repeating report slots, rolling month/year plans, unmanaged capacity, and all-or-clean failure handling.
- Full unit and UI verification passed on the iPhone 17 iOS 26.2 simulator: 72 unit tests and 5 UI tests, with zero failures.
- Debug and Release simulator builds passed without compiler warnings.
- `xcodegen generate` and `git diff --check` passed.

## Remaining limitations

- Local notifications cannot replenish themselves while the app never receives runtime; reopening FlashCount performs the next rolling rebuild.
- Delivery remains subject to notification permission, Focus modes, and device settings.
