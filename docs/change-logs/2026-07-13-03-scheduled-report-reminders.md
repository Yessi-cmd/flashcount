# Scheduled report reminders

## Purpose

Complete the existing report-reminder preference domain with user-facing settings, local notification scheduling, and navigation from a delivered notification to the requested report period.

## Affected files

- `FlashCount/Core/ReportRoute.swift`
- `FlashCount/FlashCountApp.swift`
- `FlashCount/Services/DataServices/DataBackupService.swift`
- `FlashCount/Services/SystemServices/ReminderNotificationService.swift`
- `FlashCount/Services/SystemServices/ReportReminderNotificationService.swift`
- `FlashCount/Views/MainTabView.swift`
- `FlashCount/Views/Report/ReportView.swift`
- `FlashCount/Views/Report/ReportReminderSettingsView.swift`
- `FlashCountTests/ReportDomainTests.swift`

## Behaviour changes

- Users can enable daily, weekly, monthly, and yearly report reminders from the report toolbar and choose delivery details.
- Report reminders use only local notifications. Monthly and yearly dates that do not exist are clamped to the last day of the month.
- Tapping a report notification selects the report tab and requested period, including after a cold launch.
- Authorized schedules are refreshed on app startup, and reminder preferences are included in local JSON backups.

## Verification performed

- Added unit coverage for repeating daily/weekly plans, month-end and leap-day clamping, and cold-launch route persistence.
- `xcodegen generate` completed successfully and regenerated the Xcode project from `project.yml`.
- An unsigned Debug build for the generic iOS Simulator destination succeeded, including embedded-widget validation.
- All 59 unit tests passed on an iPhone 17 Pro simulator running iOS 26.2.
- All 4 UI smoke tests passed on the same simulator.
- `git diff --check` completed without whitespace errors; the generated project lists the app, unit-test, UI-test, and Widget targets.

## Remaining limitations

- iOS notification delivery still depends on system notification permissions, Focus modes, and device settings.
- Monthly reminders are scheduled for the next twelve occurrences and yearly reminders for the next three; opening the app refreshes that rolling window.
