# Finance invariants and onboarding completion

## Purpose

Preserve recurrence anchors and prevent invalid local money values or incomplete onboarding sessions from being treated as valid state.

## Affected files

- Money validation and asset-domain models and editors.
- Recurring-rule skip handling.
- Main-tab and onboarding presentation.

## Behaviour changes

- Month-end recurring rules keep their original anchor when an occurrence is skipped.
- Account and savings values cannot be negative; physical-asset residual value and daily-cost inputs are bounded.
- Model progress and depreciation calculations defensively remain within valid ranges.
- First-run onboarding is marked complete only after the user taps the completion button.

## Verification performed

- Added regression coverage for month-end skip anchors, invalid asset values, and clamped savings progress.
- UI smoke coverage confirms onboarding completion reaches the main interface.
- Ran the complete unit and UI test scheme: 25 unit tests and 2 UI tests passed.

## Remaining limitations

- Existing invalid values are clamped when edited or calculated; the Settings repair tool remains the explicit bulk-repair entry point.
