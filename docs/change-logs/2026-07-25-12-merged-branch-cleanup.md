# 已合并分支清理

## 目的

删除已完全合入 `origin/main` 的历史分支，减少 GitHub 与本地仓库的分支杂项，并遵循以 `main` 为唯一长期分支的约定。

## 影响文件

- `docs/change-logs/2026-07-25-12-merged-branch-cleanup.md`
- GitHub 远端分支：`agent/architecture-refactor`、`agent/audit-remediation`、`codex/back-tap-quick-entry`、`refactor/project-structure`
- 本地分支：`agent/architecture-refactor`、`agent/audit-remediation`、`refactor/project-structure`

## 行为变化

- 已删除上述 4 个完全合入 `origin/main` 的远端分支。
- 已删除上述 3 个完全合入 `origin/main` 的本地分支。
- 未删除 `codex/add-haircut-category`，因为它包含 13 个尚未合入的提交。

## 验证结果

- 在删除前以 `git branch --merged origin/main` 确认所有已删除分支均完全合入远端主分支。
- `git push origin --delete` 成功删除全部 4 个远端分支。
- `git fetch --prune origin` 后确认远端只保留 `main` 与未合入的 `codex/add-haircut-category`。

## 剩余限制

- 本地 `main` 与 `origin/main` 仍有分叉（本地独有 28 个提交、同时落后 38 个提交），因此未重置或删除，以免丢失未合入历史。
- 当前工作分支与两个由 `.claude/worktrees/` 占用的本地分支亦未删除；其远端上游已删除或不存在。
- 其余本地 `codex/scrub-*` 分支含未合入内容，需逐一决定保留、合并或废弃后才能继续清理。
