# FlashCount Agent Instructions

## Change log requirement

- Create a Markdown change log in `docs/change-logs/` for every coherent code-change batch.
- Name entries `YYYY-MM-DD-NN-brief-topic.md`.
- Each entry must state the purpose, affected files, behaviour changes, verification performed, and any remaining limitations.
- Do not overwrite or remove existing user changes. Record only changes made in the current batch.

## Project rules

- Edit `project.yml`, not `FlashCount.xcodeproj/project.pbxproj`; regenerate the project with XcodeGen afterward.
- Preserve the local-first privacy model. Do not add network dependencies unless explicitly requested.
- Use `Decimal` for money and make changes to related persisted data atomically where possible.

## IPA packaging rules

- Keep IPA outputs in `build/` and use only the canonical names `FlashCount.ipa` and `FlashCount-AltStore.ipa`.
- Never add version numbers, build numbers, dates, or suffix copies to IPA filenames. A rebuild replaces the canonical file only after verification succeeds.
- Keep at most one IPA per distribution channel. Remove obsolete IPA variants after a successful replacement.
- Build AltStore packages with `scripts/package-altstore.sh`. They must contain only the unsigned main app, with no Widget extension, code signature, or provisioning profile.
- Never publish a development-signed IPA. Inspect an IPA for embedded provisioning profiles and personal/device identifiers before any external upload.
- Follow the full packaging and verification policy in `docs/packaging.md`.
