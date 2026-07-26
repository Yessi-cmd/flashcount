# 2026-07-26 — 唯一 Agent 文档 + 以 ADR 取代逐批 change log

## 背景

仓库同时维护 4 份 AI 指导文档（`CLAUDE.md`、`AGENTS.md`、`docs/agent.md`、`docs/AI_PROJECT_CONTEXT.md`），全部被 gitignore、无版本管理。审查（见 `docs/remediation-plan.md`）确认其中最旧的一份 19 天未更新，含 7 处与代码事实相反的陈述（测试是否存在、Widget 是否接入、Reminder 存储方案、备份精度与版本号、Schema 结构、周期规则收支切换）。误导性文档直接降低每次 AI 会话的产出质量。

同时，`AGENTS.md` 强制"每批改动写一份 change log"，两个月累计 83 份文件（峰值一天 22 份），内容与 git 提交历史重复，维护成本真实、读者稀少。

## 决定

1. `AGENTS.md` 是唯一的 agent 指导文档，**纳入版本库**；`CLAUDE.md` 仅保留一行 `@AGENTS.md` 导入。删除 `docs/agent.md` 与 `docs/AI_PROJECT_CONTEXT.md`。
2. 结构性变更（增删 target、迁移存储、增删模型、Schema 升版）必须在同一批改动中同步更新 `AGENTS.md`。
3. 废止"每批改动写 change log"制度。`docs/change-logs/` 封存为历史档案，不再新增。git 提交信息即变更记录。
4. 重大架构决策写入 `docs/decisions/`（本文件为第一篇）：背景 → 决定 → 后果，文件名 `YYYY-MM-DD-brief-topic.md`。

## 后果

- 文档进入 git 后，过期即出现在 diff 里，腐烂可被审查发现。
- 放弃 change log 仪式后，提交信息质量成为唯一变更记录，需保持自解释。
- 历史 change logs 仍可用于考古，但不再作为流程要求。
