# Persistence failure recovery

## Purpose

Keep reminders, notifications, transactions, backups, and settings consistent when local persistence fails or an import is interrupted.

## Affected files

- Reminder storage, notification scheduling, reminder UI, and transaction undo handling.
- Recurring-rule and budget save paths.
- Backup import validation, journaling, and startup recovery.

## Behaviour changes

- Reminder files are committed before UI state or notification side effects change.
- Failed transaction undo remains available for retry and no longer reports success.
- SwiftData save failures roll back staged mutations consistently.
- Backup money, UUIDs, relationships, and domain constraints are validated before mutation.
- Interrupted cross-store imports are replayed from a local journal on the next startup.

## Verification performed

- Added regression coverage for invalid backup money, duplicate UUID rejection, reminder write failures, and failed reminder mutations.
- Ran the complete unit and UI test scheme: 25 unit tests and 2 UI tests passed.

## Remaining limitations

- Notification delivery and interruption levels still require a physical-device check.
- Separate local stores cannot share one operating-system transaction; the journal provides idempotent recovery instead.
