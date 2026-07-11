# Backup preview, settings, and import modes

## Purpose

Finish the data-management priority work: back up all current app preferences and let the user choose a reviewed merge or replacement import.

## Changes

- Backups now include appearance, asset-balance visibility, onboarding completion, payday, and reminders.
- The file picker decodes and displays a backup summary before any data changes.
- Import offers merge and destructive replacement modes.
- Replacement clears SwiftData models and reminders before importing the validated backup.

## Limitation

Replacement is intentionally exposed as a destructive action. It validates the backup before clearing storage, but device-level storage failure during the subsequent import still requires restoring from a separate backup.
