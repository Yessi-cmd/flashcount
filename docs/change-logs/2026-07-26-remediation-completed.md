# FlashCount 整改执行清单（已完成）

> 生成日期：2026-07-26。**执行完成日期：2026-07-26。** 全部阶段完成，验证方式：121 个单元测试 + 17 个 UI 冒烟测试全绿，Debug 与 Release 双配置构建通过。
>
> 本文件按自身规定归档至 `docs/change-logs/`；持久性结论已沉淀进 `AGENTS.md`。

## 执行结果总览

| 阶段 | 结果 |
|------|------|
| 1. Git 大扫除 | ✅ 本地只剩 `main`；worktree/僵尸分支清除（`archive/*` 标签兜底）；`.claude/` 入 gitignore |
| 2. AI 文档四合一 | ✅ `AGENTS.md` 唯一真源并入库，`CLAUDE.md` 一行导入；7 处过期陈述全部修正；change log 制度改为 `docs/decisions/` ADR |
| 3. Ledger 排雷 | ✅ `DefaultDataService` 删账本前强制空校验（`ConsolidationError`）；新增 `LedgerConsolidationTests` 回归；**决策 A：单账本定性** |
| 4. 上帝文件瘦身 | ✅ DataBackupService 1305→5 文件；LedgerView 1284→5 文件；ReportView 1152→4 文件；FinanceDomainTests 1074→5 文件；追加 QuickEntryView 910→3 文件。**全仓库无 >800 行文件** |
| 5. iOS 26 收敛 | ✅ 修复真实回归：账本工具栏 5 按钮在 iOS 26 溢出为系统 More 菜单——收纳为 筛选+行动中心+自有「更多」菜单（8 个 UI 测试复活）；README/project.yml 对齐实际工具链 Xcode 26 |
| 6. Widget 决断 | ✅ **决策 B：砍除**——118 行仅跳转、AltStore 包本就不含；同步清理引导/教程/README/打包文档文案 |
| 7. 零碎收尾 | ✅ 删除失败改为用户可见弹窗（资产/实物资产）；print→os.Logger；签名 Team 移入 gitignored `project.local.yml`（XcodeGen optional include）；VisualExploration 全量 `#if DEBUG`（Release 二进制不再包含 ~1,400 行实验代码）；12.5MB 设计截图与探索文档归档删除 |
| 附加 | ✅ 记账页 UI 比例重排：压缩 iOS 26 玻璃键盘与保存条 ~50pt，分类卡片不再被拦腰截断，点按目标保持 ≥44pt |

## 决策记录

- **阶段 2 · change log 制度**：废除逐批手写 change log；重大架构决策写 `docs/decisions/`（首篇 ADR：`2026-07-26-single-agent-doc-and-adr-records.md`）。`docs/change-logs/` 封存为历史档案。
- **阶段 3 · 账本形态**：A——正式接受单账本。`Ledger` 为不可删除的内部概念，UI 永不暴露删除入口；guard + 回归测试为永久防线。
- **阶段 5 · Xcode 承诺**：README 改为「Xcode 26 或更高」，`project.yml` `xcodeVersion: 26.0`；旧 SDK 编译回退保留但不再声明支持。
- **阶段 6 · Widget**：B——移除 target；如未来要做带数据的 Widget，从 git 历史恢复并配 App Group。

## 有意偏离计划之处

- 4b 主文件目标 <400 行未严格达成（LedgerView 424 行），但远低于 800 行验收线；换来的是把 `QuickEntryView` 也纳入拆分（原计划未列）。
- 阶段 5 未合并 `MainTabView` 的 modern/legacy 双轨按钮：两套视觉是有意的分代设计，已集中经由 `DesignSystem` 与 `LiquidGlassContainer` 管理，合并的回归风险大于收益。液态玻璃/旧样式的成对视图变体同理保留。
- 阶段 7 `try?` 审计结论：23 处中绝大多数是有意的优雅降级（DEBUG 夹具、通知尽力而为、解析回退），仅 2 处删除失败静默与 1 处 print 属于真问题并已修复。

## 🚫 继续保持不动的资产

- 金钱纪律：全 `Decimal`、金额恒正 + `isExpense` 定符号
- `CodableMoney` 字符串编码及旧格式兼容
- SchemaV2 + `FlashCountMigrationPlan` 显式迁移体系
- 启动失败的非破坏性兜底文案与重试路径
- `safeSave()` 模式与隐私锁（后台遮罩 + Face ID 门控）
- 零网络：全仓库无 `URLSession`
