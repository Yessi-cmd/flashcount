# Widget extension metadata

## Purpose

Keep the WidgetKit extension metadata in the XcodeGen source of truth rather than a generated plist that XcodeGen overwrites.

## Affected files

- `project.yml`
- `FlashCountWidget/Info.plist` (generated)

## Behaviour changes

The generated widget Info.plist now declares the `com.apple.widgetkit-extension` extension point.

## Verification

Regenerate with `xcodegen generate`, then inspect the plist with `plutil -p FlashCountWidget/Info.plist`.
