# Single-ledger direction and shortcut-extension rollback

## Product decision

The app is single-ledger. Widget, Siri/Shortcuts, and deep-link quick entry are not part of the current product scope.

## Changes

- Removed the newly added WidgetKit target and custom URL scheme from `project.yml`.
- Removed the intent/deep-link hand-off code added in the previous batch.
- Kept the pre-existing Widget source directory untouched but unconnected to the application target.

## Verification

Project regeneration will return to the app and test targets only.
