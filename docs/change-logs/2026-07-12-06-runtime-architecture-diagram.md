# Runtime architecture diagram

## Purpose

Document FlashCount's current runtime component boundaries, local data paths, and on-device system integrations in a single browsable architecture artifact.

## Affected files

- `docs/architecture.html`
- `docs/change-logs/2026-07-12-06-runtime-architecture-diagram.md`

## Behaviour changes

- Added a self-contained architecture diagram with dark/light theme switching and PNG, JPEG, WebP, and SVG export controls.
- Documented the main path from App Intents and app launch through `AppRootView`, SwiftUI feature views, local data access and domain logic, and SwiftData persistence.
- Documented the separate UserDefaults, privacy lock, backup/CSV, reminder JSON, and local notification paths.
- Marked the existing Widget source as not currently wired into a target in `project.yml`.
- No application runtime behaviour changed.

## Verification performed

- Rendered the artifact with the Archify architecture renderer.
- Ran Archify's architecture validation and generated-HTML checks successfully, including finite SVG values, orthogonal arrows, and legend clearance.
- Rendered a Quick Look PNG preview and visually checked component labels, connections, sandbox boundaries, legend, and summary cards.
- Checked the final diff for whitespace errors.

## Remaining limitations

- The diagram is a static source-code snapshot and must be updated when runtime integrations or persistence boundaries change.
- It intentionally groups individual feature views, model types, and finance services to keep the primary runtime path readable.
- The renderer's optional AJV schema package was not installed; built-in layout validation and generated-HTML checks still completed successfully.
