# Remove Local AI Guidance From Git

## Purpose

Keep local AI agent instructions and generated project context out of the
published repository while preserving the files in each developer's local
checkout.

## Affected Files

- `.gitignore`
- `AGENTS.md` (removed from Git tracking; retained locally)
- `CLAUDE.md` (removed from Git tracking; retained locally)
- `docs/AI_PROJECT_CONTEXT.md` (removed from Git tracking; retained locally)
- `docs/agent.md` (removed from Git tracking; retained locally)
- `docs/change-logs/2026-07-24-01-remove-local-ai-guidance-from-git.md`

## Behaviour Changes

- The four local AI guidance/context files are no longer published from Git.
- The paths are ignored so local copies are not accidentally recommitted.
- Application behaviour is unchanged.

## Verification Performed

- Confirmed the four paths are absent from the staged Git index.
- Confirmed all four paths match the new `.gitignore` rules.
- Confirmed all four files still exist in the local checkout.
- Ran `git diff --cached --check` with no whitespace errors.

## Remaining Limitations

- GitHub may retain inaccessible cached objects for a period after history is
  rewritten.
- Existing forks or external clones cannot be modified from this repository.
