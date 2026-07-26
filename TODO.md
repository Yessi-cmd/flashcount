# TODO

自主维护待办。来源：代码注释扫描、编译警告、超长函数、文档一致性、覆盖率。
完成项移入 `DONE.md`。

## 扫描基线（2026-07-27）

- `TODO`/`FIXME`/`HACK` 注释：**0 条**（grep 命中的均为正常中文注释）
- 应用目标编译警告：**0 条**（`xcodebuild clean build`）
- 无 SwiftLint 配置且未安装 → lint 信号采用 Swift 编译器警告；不为此引入新工具链依赖
- 超过 50 行的函数：42 个（含测试与静态数据表）

## 高

- [x] **AGENTS.md 未反映本轮结构变化**（已完成，见 DONE.md） — 新增 `QuickEntryFeedbackCenter` 服务未进 Services 表；记账保存反馈、隐私锁解锁流程、底栏中央按钮行为、分类格子交互模型都已改变，Caveats 仍是旧描述。AGENTS.md 自己规定结构变化必须同批更新，且它是 agent 唯一真源。影响范围：文档，无代码风险。
- [x] **本轮 UX 改动缺 ADR**（已完成，见 DONE.md） — `docs/decisions/` 按规定应记录重大决策。至少两项够格：分类格子交互模型（单点即选 + 明确的换小类入口，且两种失败方案要留下"别再试"的记录）、隐私锁放宽（去掉确认弹窗与切 tab 重锁）。影响范围：文档。
- [ ] **新增三个类型无测试** — `QuickEntryFeedbackCenter`（提示条生命周期与过期）、`AdaptiveMetricRow`/`AdaptiveMetric`（横纵排切换）、`QuickEntrySavedToast`。前者是纯逻辑，值得单测。影响范围：新增测试文件。
- [ ] **补齐逻辑层覆盖率** — 基线：逻辑层合计 ≈82.6%，全目标 43.24%（约 80% 计数行是视图代码，见 `BLOCKERS.md` 说明 85% 总量目标为何不成立）。按未覆盖行排序推进 `Services/DataServices`（78.1%，2671 行）与 `Services/FinanceServices`（83.8%，3486 行）。影响范围：测试。

## 中

- [ ] **`BackupImporter.importJSON()` 455 行** — 单个函数承担全部模型的导入。按模型分组拆成私有步骤，行为不变；`FinanceDomainTests+Backup` 可兜底。影响范围：备份导入，风险中等，务必先看测试覆盖。
- [ ] **`DataHealthService.scan()` 203 行** — 各项健康检查可拆为独立私有方法，顺带让单项检查可被单测。影响范围：数据健康中心。
- [ ] **`BackupExporter.exportJSON()` 145 行** — 同上，按模型分组。影响范围：备份导出。
- [ ] **`LedgerPresentation.makePresentation()` 118 行** — 分组/汇总/筛选三段职责混在一起。影响范围：账本列表呈现。
- [ ] **README 与代码状态的两处出入** — 报表一栏未提发薪周期报（实际有五种周期）；测试示例设备为 iPhone 16，AGENTS.md 与本地惯例是 iPhone 17 Pro。影响范围：文档。

## 低

- [ ] **视图层超长 body** — `RecurringRulesView.ruleCard`(120)、`ReportChartCards.timeBucketBarChart`(99)、`LedgerSections.transactionRow`(97)、`SavingsGoalView.goalCard`(93)、`InstallmentBillView.billCard`(90) 等。声明式代码长不等于坏，只拆分能独立复用或有条件分支的部分。影响范围：视图，纯重构。
- [ ] **`Category.expenseCategoryGroups()` 167 行 / `incomeCategoryGroups()` 68 行** — 静态数据表，拆分收益低，仅在需要外部化分类种子时再动。影响范围：分类种子数据。
- [ ] **`FlashCountApp.prepareActionCenterUITestDataIfNeeded()` 95 行** — DEBUG-only 测试夹具，可移到独立文件让 `FlashCountApp.swift` 回到职责单一。影响范围：仅 DEBUG。
