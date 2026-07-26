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
- [x] **新增三个类型无测试**（已完成，见 DONE.md） — `QuickEntryFeedbackCenter`（提示条生命周期与过期）、`AdaptiveMetricRow`/`AdaptiveMetric`（横纵排切换）、`QuickEntrySavedToast`。前者是纯逻辑，值得单测。影响范围：新增测试文件。
- [ ] **补齐逻辑层覆盖率** — 基线：逻辑层合计 ≈82.6%，全目标 43.24%（约 80% 计数行是视图代码，见 `BLOCKERS.md` 说明 85% 总量目标为何不成立）。按未覆盖行排序推进 `Services/DataServices`（78.1%，2671 行）与 `Services/FinanceServices`（83.8%，3486 行）。影响范围：测试。

## 中

- [x] **记账键盘输入与累加逻辑不可单测**（已完成，见 DONE.md） — `handleKeyPress` 的位数限制（整数 12 位、小数 2 位、`00` 与 `.` 的特殊处理）和 `accumulateAmount()`/`resolvedAmount()` 的金额累加都写在 `QuickEntryView` 的扩展里、依赖 `@State`，只能靠 UI 测试间接摸到。AGENTS.md 把 Decimal 金额正确性列为关键约定，这段最该有单测。抽成纯类型后可完整覆盖。影响范围：记账页输入，有 UI 测试兜底。

- [ ] **`BackupImporter.importJSON()` 455 行 —— 先补覆盖率，再拆** — 实测该文件只有 69.6% 覆盖（`DataServices` 里最低的之一），是这批长函数里兜底最弱的。顺序刻意定为先补导入路径的测试、再按模型分组拆分；反过来做等于在没有安全网的地方动数据导入。影响范围：备份导入。
- [x] **`DataHealthService.scan()` 203 行**（已完成，见 DONE.md） — 各项健康检查可拆为独立私有方法，顺带让单项检查可被单测。影响范围：数据健康中心。
- [x] **`BackupExporter.exportJSON()` 145 行 —— 判定为不该拆**（见 DONE.md）
- [ ] **`BackupImporter.importJSON()` 第二批：头部小节** — 剩余 362 行里，分类／账本／交易／周期规则／周期发生项／预算／资金池之间靠 `categoryMap`/`ledgerMap`/`ruleMap`/`transactionMap`/`importedTransactionDelta` 互相传值，需要先引入一个承载中间状态的类型才能拆。覆盖率 78.3%，动之前建议再补几条（replace 模式、旧版 assets 折算、cashPoolStates 三个分支）。影响范围：备份导入。
- [ ] **补齐公开接口文档注释（剩 73 个）** — 269 个顶层类型中原缺 147 个，已完成 Core(8)、Models(9)、BudgetServices(8)、DataHealth 家族(11)、FinanceServices(38)。剩余：`Services/SystemServices` 20、`Services/DataServices` 8（合计服务层 28），视图层 44（SwiftUI 视图多为自解释，价值最低，建议只补有非显然约束的那些）。要求写出不变量与「为什么存在」，复述类型名的注释不算。影响范围：文档注释。
- [ ] **`LedgerPresentation.makePresentation()` 118 行** — 分组/汇总/筛选三段职责混在一起。影响范围：账本列表呈现。
- [x] **README 与代码状态的两处出入**（已完成，见 DONE.md） — 报表一栏未提发薪周期报（实际有五种周期）；测试示例设备为 iPhone 16，AGENTS.md 与本地惯例是 iPhone 17 Pro。影响范围：文档。

## 低

- [ ] **视图层超长 body** — `RecurringRulesView.ruleCard`(120)、`ReportChartCards.timeBucketBarChart`(99)、`LedgerSections.transactionRow`(97)、`SavingsGoalView.goalCard`(93)、`InstallmentBillView.billCard`(90) 等。声明式代码长不等于坏，只拆分能独立复用或有条件分支的部分。影响范围：视图，纯重构。
- [ ] **`Category.expenseCategoryGroups()` 167 行 / `incomeCategoryGroups()` 68 行** — 静态数据表，拆分收益低，仅在需要外部化分类种子时再动。影响范围：分类种子数据。
- [ ] **`FlashCountApp.prepareActionCenterUITestDataIfNeeded()` 95 行** — DEBUG-only 测试夹具，可移到独立文件让 `FlashCountApp.swift` 回到职责单一。影响范围：仅 DEBUG。
