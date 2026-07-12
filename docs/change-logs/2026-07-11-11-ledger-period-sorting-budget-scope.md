# 账本周期、排序与日常预算范围

## 目的

修复账本首页汇总标题与日期筛选不同步的问题，明确区分自然月和发薪周期，补充交易正序/倒序排列，并把日常预算从写死的大类规则升级为用户可配置、单笔可覆盖的明确范围。同时统一分类短按菜单与 B 方向视觉。

## 影响文件

- `FlashCount.xcodeproj/project.pbxproj`（由 XcodeGen 重新生成）
- `FlashCount/FlashCountApp.swift`
- `FlashCount/Models/Category.swift`
- `FlashCount/Models/Transaction.swift`
- `FlashCount/Services/BudgetServices/BudgetReminderService.swift`
- `FlashCount/Services/DataServices/CSVTransactionService.swift`
- `FlashCount/Services/DataServices/DataBackupService.swift`
- `FlashCount/Views/Budget/BudgetView.swift`
- `FlashCount/Views/Budget/DailyBudgetScopeView.swift`
- `FlashCount/Views/Components/CategoryPickerComponents.swift`
- `FlashCount/Views/Ledger/EditTransactionView.swift`
- `FlashCount/Views/Ledger/FilterSheetView.swift`
- `FlashCount/Views/Ledger/LedgerView.swift`
- `FlashCount/Views/QuickEntry/QuickEntryView.swift`
- `FlashCountTests/FinanceDomainTests.swift`
- `docs/ledger-budget-scope-screenshots/`

## 行为变化

- 账本默认时间范围改为“本周期”，汇总卡明确显示“本周期支出 / 收入 / 结余”和周期起止日期。
- 增加独立“本月”选项；今天、本周、本周期、本月、全部和自定义范围都会同步更新汇总标题、金额与交易列表。
- 今天、本周和本月使用完整、封闭的自然日期区间，不再把未来日期误计入当前范围。
- 筛选面板增加“时间 / 金额”和“正序 / 倒序”组合，支持最新、最早、金额从高到低和金额从低到高四种排列；账本页显示当前排列入口。
- 有子分类的大类改为短按直接打开具体分类菜单，长按仍兼容；菜单减少多色扇区、旋转和重阴影，统一为 B 方向的实体背景、墨绿强调和细边界。
- 日常预算默认范围收紧到餐饮、通勤和日用品等高频可控小类；服饰鞋包、聚餐、火车飞机、固定账单和大件消费默认排除。
- 预算页新增边界明确的“日常预算范围”入口；用户可以逐个分类调整，也可以按组全部纳入或全部排除，并可恢复默认规则。
- 快速记账首屏新增紧凑“日常预算”开关；开关未操作时跟随分类范围，操作后只覆盖当前一笔。编辑既有交易时也可修改或恢复跟随分类。
- 删除撤销会保留单笔日常预算覆盖值。
- 备份格式升级为 `1.7.0`，分类范围与单笔覆盖均参与 JSON 备份恢复；旧备份缺少字段时继续使用默认规则。
- CSV 新增可选 `dailyBudget` 列，支持 `inherit`、`include` 和 `exclude`，旧六列 CSV 继续兼容。
- 新增仅在 DEBUG 生效的视觉检查启动参数，用于稳定检查范围配置、快速记账和分类菜单，不影响正式启动路径。

## 验证

- 使用 XcodeGen 重新生成工程。
- 在 iPhone 17 Pro（iOS 26.2）模拟器运行已有数据存储，确认新增可选字段可自动兼容且 App 正常启动。
- 人工检查本周期首页、预算范围入口、分类范围设置、快速记账单笔开关和分类短按菜单截图。
- 执行 `xcodebuild test`：11 项测试通过，0 项失败；新增覆盖自然月/发薪周期区分、服饰默认排除、分类/单笔覆盖优先级及备份恢复。
- 执行 `git diff --check`：未发现空白字符错误。

## 剩余限制

- 金额排序时交易不再按日期分组，而是作为一个金额排序结果展示；时间排序仍保留按日分组。
- 分类范围配置针对当前本地分类持久化；之后新建的分类在用户明确选择前默认不计入日常预算。
- 分类菜单仍保留原有圆盘拨动交互，只统一视觉与短按入口，没有改成列表式菜单。
- 尚未在真实 Taptic Engine 和所有 Dynamic Type 尺寸下逐项检查菜单拨动与紧凑记账开关。
