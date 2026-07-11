# Startup data preparation error propagation

## Purpose

Prevent failed SwiftData fetches during startup from being treated as empty storage and accidentally causing default-data writes or deletions.

## Affected files

- `FlashCount/Services/DataServices/DefaultDataService.swift`

## Behaviour changes

- All startup fetches now throw to one top-level handler.
- Any startup preparation failure rolls back the model context and skips recurring-rule processing for that launch.

## Verification

Reviewed all former empty-array fallbacks in this service. Project generation succeeds with the current configuration.
