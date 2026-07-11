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
