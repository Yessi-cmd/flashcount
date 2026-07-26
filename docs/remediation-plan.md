# FlashCount 整改执行清单

> 生成日期：2026-07-26。基于对当前工作区（`codex/back-tap-quick-entry` @ `30380e6`）的全面审查。
> 本文档取代 `docs/improvement-plan.md` 的优先级排序（该文件保留作架构拆分参考）。
>
> **用法**：按阶段从上往下做，完成一项勾一项。每个阶段独立可交付，做完跑一次「验收」再进下一阶段。
> 代码类改动的通用验收命令：
>
> ```bash
> xcodegen generate
> xcodebuild test -project FlashCount.xcodeproj -scheme FlashCount \
>   -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
> ```

## 现状快照（2026-07-26）

| 维度 | 数字 |
|------|------|
| 主 App 代码量 | 27,537 行 Swift（不含测试与 worktree 副本） |
| 测试 | 13 个单测文件 + 1 个 UI 冒烟测试，CI 真跑 |
| 巨型文件 | DataBackupService 1305 / LedgerView 1284（单 struct）/ ReportView 1152 / FinanceDomainTests 1074 |
| 本地分支 | 8 条（main 已与远端分叉，4 条 scrub 僵尸，2 条 worktree 遗留） |
| AI 指导文档 | 4 份，全部 gitignore，最旧的 19 天未更新且含 5+ 处错误陈述 |
| change-logs | 83 份 |
| iOS 26 可用性分叉 | 23 处 `iOS 26` + 7 处 `#if compiler/canImport` |

---

## 阶段 0：安全垫（5 分钟，P0）

- [ ] 确认当前没有想保留的未提交**代码**改动：`git status --short`（当前应只有 `.claude/`、两份 07-25 changelog、`docs/improvement-plan.md`、本文件为 untracked）
- [ ] 打一个总备份标签，兜底一切后续删除：

```bash
git tag archive/pre-cleanup-2026-07-26 HEAD
```

---

## 阶段 1：Git 大扫除（~30 分钟，P0）

**背景**：远端 `origin/main`（`30380e6`）就是当前工作状态；本地 `main` 是一条陈旧的 rebase 残线（唯一独有提交 `ae64847` 与 HEAD 上的 `a66c4a0` 同名，其余全部 patch-equivalent，已用 `git log --cherry-mark` 验证）。scrub 分支上的"独有"提交也都是 main 历史的改写副本。

### 1.1 给要删的东西打存档标签（零风险删除的前提）

- [ ] 执行：

```bash
git tag archive/main-stale main
for b in codex/scrub-agent-architecture-refactor \
         codex/scrub-agent-audit-remediation \
         codex/scrub-codex-add-haircut-category \
         codex/scrub-refactor-project-structure \
         codex/add-haircut-category; do
  git tag "archive/${b//\//-}" "$b"
done
```

> 标签只留在本地，**不要 push**。一个月后确认无事可全删：`git tag -l 'archive/*' | xargs git tag -d`

### 1.2 清理 agent worktree 残骸

两个 worktree（`.claude/worktrees/agent-*`）的分支**已合并**进 HEAD，但工作区是**脏的**（`ReportService.swift`、`FlashCountApp.swift` 等有未提交改动——是 7 月中旬"定时报表"功能的草稿，该功能已在 main 以 `6ec9080`/`96601b3` 落地）。

- [ ] 先扫一眼脏改动，确认没有想捞的东西：

```bash
git -C .claude/worktrees/agent-aae5d886f783335b2 diff | head -100
git -C .claude/worktrees/agent-acbad7081cf08ab2f diff | head -100
```

- [ ] 移除 worktree 和对应分支：

```bash
git worktree remove --force .claude/worktrees/agent-aae5d886f783335b2
git worktree remove --force .claude/worktrees/agent-acbad7081cf08ab2f
git branch -d worktree-agent-aae5d886f783335b2 worktree-agent-acbad7081cf08ab2f
```

### 1.3 把 main 拉回现实，回到 main 上干活

- [ ] 执行：

```bash
git checkout main
git reset --hard origin/main        # origin/main == 原工作分支 HEAD，内容零变化
git branch -d codex/back-tap-quick-entry   # 已合并，-d 会安全通过
```

### 1.4 删除僵尸分支（已在 1.1 打过存档标签）

- [ ] 本地：

```bash
git branch -D codex/scrub-agent-architecture-refactor \
              codex/scrub-agent-audit-remediation \
              codex/scrub-codex-add-haircut-category \
              codex/scrub-refactor-project-structure \
              codex/add-haircut-category
```

- [ ] 远端旧分支（category wheel 功能早已在 main 上）：

```bash
git push origin --delete codex/add-haircut-category
```

### 1.5 gitignore 补漏

- [ ] `.gitignore` 追加一行：`/.claude/`（`settings.local.json` 属于个人本地配置，不入库）
- [ ] 顺手清理 Finder 垃圾：`find . -name .DS_Store -delete`

### 1.6 处理 untracked 文档

- [ ] 提交两份 07-25 changelog（`main-default-branch`、`merged-branch-cleanup`）
- [ ] 提交 `docs/improvement-plan.md`（文件头加一行：「优先级排序已由 `docs/remediation-plan.md` 取代，本文保留作拆分方案参考」）
- [ ] 提交本文件

### ✅ 阶段 1 验收

- [ ] `git branch` 只剩 `main`
- [ ] `git worktree list` 只剩主目录
- [ ] `git status` 干净
- [ ] `git log origin/main..main` 为空（本地与远端一致）
- [ ] 以后所有日常工作直接在 `main` 上进行（这本来就是 AGENTS.md 的规矩）

---

## 阶段 2：AI 文档四合一（~1 小时，P0）

**背景**：`CLAUDE.md`（7月7日）、`docs/agent.md`（自述 7月5日）、`docs/AI_PROJECT_CONTEXT.md`（自述 7月11日）、`AGENTS.md`（7月25日）四份重叠文档全部被 gitignore，无版本管理，互相矛盾。CLAUDE.md 已确认的错误陈述：

| # | CLAUDE.md 说 | 实际情况 |
|---|---|---|
| 1 | 「不存在测试 target」 | `project.yml` 已有 FlashCountTests + FlashCountUITests，CI 在模拟器上跑全部测试 |
| 2 | 「FlashCountWidget 未接入 project.yml」 | 已作为依赖 embed 进主 target |
| 3 | 「ReminderItem 存 JSON 以规避迁移风险」 | 已迁入 SwiftData（`423ce68`），注意 `ReminderStore.swift` 是否只剩迁移用途 |
| 4 | 「DataBackupService 将 Decimal→Double 导出，有精度隐患」 | 已改为 `CodableMoney` 字符串编码，兼容旧 Double（`DataBackupService.swift:4`） |
| 5 | 「FlashCountApp.swift:10-22 列出 11 个 model」 | 现为 `Schema(versionedSchema: FlashCountSchemaV2.self)` + 迁移计划（`FlashCountApp.swift:13-16`，模型清单在 `Core/FlashCountSchema.swift`） |
| 6 | 「AddRecurringRuleView 无收入/支出切换」 | 待核实（改文档前打开该文件确认一次） |
| 7 | 备份 schema version「1.2.0」 | 待核实当前值 |

### 执行

- [ ] **选定唯一真源**：保留 `AGENTS.md` 作为唯一内容主体（工具中立的命名，内容最新）
- [ ] 把 CLAUDE.md 里仍然正确的部分（构建命令、打包流程、金钱约定、关键模式、模型关系）合并进 `AGENTS.md`，并逐条修正上表错误
- [ ] `CLAUDE.md` 改为一行引用：`@AGENTS.md`（Claude Code 支持 @ 导入；或直接做成软链接）
- [ ] 删除 `docs/agent.md` 和 `docs/AI_PROJECT_CONTEXT.md`
- [ ] 从 `.gitignore` 移除 `/AGENTS.md`、`/CLAUDE.md`、`/docs/AI_PROJECT_CONTEXT.md`、`/docs/agent.md` 四行，把留下的两个文件**提交入库**（不进 git 的文档必然腐烂，已经用 19 天证明过了）
- [ ] 在 AGENTS.md 加一条规则：「结构性变更（新增/删除 target、迁移存储方案、增删 model）必须同步更新本文件」
- [ ] **决策 changelog 制度**：83 份手写 changelog 与 git log 重复。建议把 AGENTS.md 的「每批改动必写 changelog」改为「仅重大架构决策写入 docs/decisions/」（ADR 模式），`docs/change-logs/` 封存不再新增
  - 决定：__________

### ✅ 阶段 2 验收

- [ ] 全仓库只有一份 AI 指导内容（AGENTS.md），CLAUDE.md 是它的引用
- [ ] `git ls-files | grep -E 'AGENTS|CLAUDE'` 能列出两个文件（已入库）
- [ ] 表中 7 条陈述全部与代码核对过

---

## 阶段 3：僵尸多账本排雷（~2 小时，P1 — 数据安全优先于重构）

**背景**：UI 已单账本化，但模型层保留完整多账本，且：

- `Ledger.swift:16` — `deleteRule: .cascade` → Transaction（删 Ledger = 删全部流水）
- `Ledger.swift:19` — `deleteRule: .cascade` → Budget
- `DefaultDataService.swift:84` — 存在一个真实的 `modelContext.delete(ledger)` 调用点（单账本合并路径）

### 执行

- [ ] 审计 `DefaultDataService` 合并逻辑：确认删除 ledger 前，其 transactions 和 budgets **已全部迁走**；在 `delete(ledger)` 前加硬性防线：

```swift
guard ledger.transactions.isEmpty, ledger.budgets.isEmpty else { /* 中止并上报，绝不级联删 */ }
```

- [ ] 全仓库确认再无其他 Ledger 删除路径：`grep -rn "delete(" FlashCount --include="*.swift" | grep -i ledger`
- [ ] 写回归测试：「合并/删除 ledger 的任何路径不得减少 Transaction 总数」（放进测试 target）
- [ ] **决策**（二选一）：
  - **A（推荐，工作量小）**：正式接受单账本。Ledger 降级为不可删除的内部概念，UI 永不暴露删除入口；上面的 guard + 测试作为永久防线
  - **B（工作量大）**：把多账本 UI 做回来（恢复 `selectedLedger` 筛选、账本管理页）
  - 决定：__________

### ✅ 阶段 3 验收

- [ ] guard 已落地，新增回归测试通过
- [ ] 决策已写入 AGENTS.md 的架构说明

---

## 阶段 4：上帝文件瘦身（分批数天，P1）

**背景**：service 分层其实已经不错（LedgerQueryService、TransactionMutationService、ReportAnalytics 等都在），痛点集中在 View 文件。`docs/improvement-plan.md` 确诊后三大文件反而各胖了 15%。

**铁律**：一次只拆一个文件；**纯搬家不改逻辑**；每步 `xcodegen generate` + build + test 全绿再继续；禁止顺手改行为。

### 4.1 LedgerView.swift（1284 行，单个 struct → 目标 <400 行）

- [ ] 抽出列表区块与行构建 → `Views/Ledger/LedgerListSection.swift`
- [ ] 抽出撤销横幅 + 批量选择工具栏 → `Views/Ledger/LedgerComponents.swift`（该文件已存在，并入）
- [ ] 搜索/筛选/日期区间的十几个 `@State` 收拢为一个 `LedgerFilterState`（`@Observable`），削平 body 里的分支
- [ ] 撤销状态机（`undoInfo`/`undoWorkItem`/`DispatchWorkItem`）挪进 `TransactionMutationService` 或独立的 `UndoCoordinator`

### 4.2 ReportView.swift（1152 行 → 目标 <300 行）

- [ ] 每张图表卡片独立成文件（趋势 / 分类占比 / 连续记账 streak / 智能分析…）→ `Views/Report/Cards/`
- [ ] 卡片只接收 `ReportService`/`ReportAnalytics` 产出的展示模型，不自己算

### 4.3 DataBackupService.swift（1305 行 → 四个文件）

- [ ] `BackupDTOs.swift`（所有 DTO + `CodableMoney`）
- [ ] `BackupExporter.swift` / `BackupImporter.swift` / `BackupValidator.swift`
- [ ] 拆完跑一次**真实导出→导入回环**手测，不只靠单测

### 4.4 FinanceDomainTests.swift（1074 行）

- [ ] 按域拆：BudgetTests / RecurringTests / CashPoolTests / MoneyConventionTests…（正在孵化下一个上帝文件，趁早）

### ✅ 阶段 4 验收

- [ ] 全仓库不再有 >800 行的 Swift 文件：`find FlashCount FlashCountTests -name "*.swift" | xargs wc -l | sort -rn | head -5`
- [ ] 测试数与拆分前一致且全绿

---

## 阶段 5：iOS 26 分叉收敛（~半天，P2）

**背景**：23 处 `iOS 26` 判断 + 7 处 `#if compiler/canImport` 散布各处；README 声称 Xcode 15 可构建，但 CI 只用最新 Xcode 验证，该承诺无人背书。

- [ ] 盘点：`grep -rn "iOS 26" FlashCount --include="*.swift"`
- [ ] 把液态玻璃/新样式分支收拢进 DesignSystem 适配层（如 `.adaptiveGlassButton()` 一类 modifier，内部只判断一次），调用方零 `#available`
- [ ] `MainTabView` 的 `modernTabButton`/`legacyTabButton` 双轨合并为一个组件内部分支
- [ ] **决策**：Xcode 15 支持——要么 CI 加一个旧 Xcode job 真正验证，要么 README 改口「以 CI 使用的 Xcode 版本为准」，同时更新 `project.yml` 里名不副实的 `xcodeVersion: "15.0"`
  - 决定：__________

---

## 阶段 6：Widget 决断（P2）

**背景**：Widget target 共 118 行，只做 deep link 跳转，不显示任何数据。且打包政策规定 AltStore 包**不含** Widget——若主要分发渠道是 AltStore，Widget 只对 Xcode 直装用户可见。

- [ ] **决策**（二选一）：
  - **A 做实它**：App Group + 每次保存后写一份轻量快照（今日支出 / 本周期预算余额）+ `WidgetCenter.reload`；注意快照里的敏感金额要遵守隐私锁逻辑
  - **B 砍掉**：从 `project.yml` 删 target 与 dependency，删目录——比留一个装饰品诚实
  - 决定：__________

---

## 阶段 7：零碎收尾（P2，见缝插针）

- [ ] `project.yml` Release 配置里的个人 `DEVELOPMENT_TEAM: "66WCCRKRLC"` 从公开仓库移走（留空 + 本地 gitignored xcconfig 覆盖）。AGENTS.md 自己就要求上传前检查个人标识
- [ ] 7 处 `print(` → `os.Logger`
- [ ] 审计 23 处 `try?`（多为 fetch）：用户可见路径上的静默空态至少改为可见错误提示
- [ ] `docs/` 里的截图目录（5 个 `*-screenshots/`）与两份 exploration 文档：确认是否还需要，不需要则归档删除
- [ ] `Views/VisualExploration/`（约 1,425 行设计实验代码）：运行时已被 `#if DEBUG` 拦住，但类型本身仍编进 Release 二进制——用 `#if DEBUG` 包住文件内容或移出主 target

---

## 🚫 不要动的清单（这些是资产，重构时绕开）

- **金钱纪律**：全 `Decimal`、金额恒正 + `isExpense` 定符号、`signedAmount` 派生
- **`CodableMoney`** 字符串编码及其旧格式兼容
- **SchemaV2 + FlashCountMigrationPlan** 显式迁移体系
- **启动失败的非破坏性兜底**（"没有删除任何数据"文案与重试路径）
- **`safeSave()` 模式**（裸 `try? save` 目前只剩 2 处 DEBUG 测试夹具，保持住）
- **隐私锁**：后台遮罩 + `accessibilityHidden` + Face ID 门控
- **零网络**：全仓库无 `URLSession`，这是产品承诺，任何依赖引入前先过 AGENTS.md

---

## 完成判定

- [ ] 阶段 1、2 完成（P0）：仓库只有 main、文档唯一且入库
- [ ] 阶段 3 完成（P1）：cascade 排雷 + 回归测试
- [ ] 阶段 4 完成（P1）：无 >800 行文件
- [ ] 阶段 5–7 各决策点已填写，做或明确不做
- [ ] 本文件所有 checkbox 处理完后，把有效结论沉淀进 AGENTS.md，本文件移入 `docs/change-logs/` 归档
