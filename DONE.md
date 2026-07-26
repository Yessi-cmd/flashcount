# DONE

自主维护已完成项，最新在上。每项一句话：改了什么、为什么。

## 2026-07-27

- **`BackupImporter.importJSON()` 455 行 → 362 行（第一批）** — 先抽出五个互不引用、也不参与 category/ledger/rule 映射传递的小节：实物资产、分期账单、储蓄目标、记账模板、提醒。刻意只动这些「整段可搬」的部分，顺序与状态依赖完全不变；剩下的头部小节之间靠 map 互相传值，留作第二批。195 全绿。
- **备份导入补 9 个测试（195 全绿），`BackupImporter` 覆盖率 69.6% → 78.3%** — 此前完全没被覆盖的几条路：`previewJSON`（且断言它必须只读——用户看完摘要还能取消）、文件入口与 Data 入口结果一致、同一份备份导入两次整份跳过、实物资产往返、未知资产类别／未知周期频率只跳过那一条而不拖垮整份备份。过程中一条测试的前提被证伪：我原以为同名账本会按名称复用，实际 `importJSON` 末尾与默认数据播种共用事务调用 `stageDefaultData()`，做的是单账本整理（交易归主账本、其余删除）。测试改为钉住这个更重要的不变量：导入后账本恰好一个、交易挂在它上面。
- **`DataHealthService.scan()` 从 203 行拆到 40 行以内** — 引入 `Snapshot`（十三个模型数组）与 `DuplicateTotals`/`LedgerRepair`/`DeltaRepair` 三个中间结果类型，把「取数 / 重复 UUID / 孤儿预算 / 无账本归属 / 资金池增减 / 组装 findings / 组装 plan」各归各位。行为完全不变，`DataHealthServiceTests`（该文件覆盖率 88.9%，是这批长函数里兜底最好的，因此先动它）6 个测试全绿。顺带修掉 `QuickEntryFeedbackCenter` 默认实参引用 `@MainActor` 静态属性的编译警告——lint 信号必须保持 0。
- **README 对齐当前代码** — 报表补上发薪周期报与下钻；资产一栏改写为「净资产只按资金池口径统计」，原文「汇总现金、储蓄目标、实物资产…查看净资产」与代码相反（实物估值与储蓄目标刻意不计入净资产）；测试示例设备 iPhone 16 → iPhone 17 Pro 与 AGENTS.md 统一；快速记账补上「+」累加与撤销。其余声明逐条核对无误：全仓 0 处 URLSession、iOS 17.0 / Swift 5.9 / Xcode 26、备份 CSV 提醒均本地、Siri 入口在 QuickAddIntent。
- **记账金额输入抽成 `QuickEntryAmountInput` 纯类型并补 23 个单测（186 全绿）** — 位数限制（整数 12 位、小数 2 位、整数位满后仍可输小数）、`00` 与 `.` 的边界、「+」累加（多次累加、空按忽略与报错的区分、清除累加不动当前输入）、`resolved()` 的求和与 0 元拒绝。这段是 AGENTS.md 列为关键约定的 Decimal 金额处理，此前埋在 View 扩展里依赖 `@State`，只能靠 UI 测试摸到一两个点。顺带把 `handleKeyPress` 从 46 行缩到 20 行。
- **为新增类型补单测（163 个测试，+8）** — `QuickEntryFeedbackCenterTests` 覆盖提示条生命周期（出现、被后一笔顶掉、手动收起、自行过期，以及被顶掉那笔的计时不会带走新的一笔）与文案（支出/收入前缀、补录只在非今天时出现）；`AdaptiveMetricLayoutTests` 钉住横纵排规则。为此把提示条时长改为可注入（否则测试要干等 5 秒），并把横纵排判断抽成 `AdaptiveMetricLayout` 纯函数——它是最容易被人改回 `ViewThatFits` 的地方。
- **记录 ADR：记账主流程与隐私锁的摩擦清理** — `docs/decisions/2026-07-27-quick-entry-and-privacy-friction.md`。按 AGENTS.md 规定重大决策要留背景→决定→后果，并额外记下两个被实测否决的方案（角标按钮压住格子中心、simultaneousGesture 吃掉点按），因为它们看代码看不出来、只能量出来，不写下来后人必然重走。
- **BLOCKERS.md 记录覆盖率 85% 总量目标不成立的实测依据** — 约 80% 计数行是 SwiftUI 视图代码，`VisualExploration`（3143 行 DEBUG-only）也计入分母；推到 85% 只能靠数百个慢而不稳的 UI 测试或只为实例化 view body 的空测试。改为逻辑层持续推高、视图层只补关键流程冒烟。
- **AGENTS.md 补齐本轮结构变化** — 新增 `QuickEntryFeedbackCenter` 服务条目，并把记账保存反馈、隐私锁解锁流程、底栏中央按钮、分类格子交互模型、`AdaptiveMetricRow` 为何不用 `ViewThatFits`、账本吸顶与 badge 口径、打卡热力图方格写进 Caveats。AGENTS.md 自己规定结构变化必须同批更新，而它是 agent 的唯一真源，落后一轮就会把后来者引向已被实测否决的方案。
