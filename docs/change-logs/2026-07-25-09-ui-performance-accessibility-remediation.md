# UI、性能与无障碍缺陷修复

## 目的

落实 UI、性能与无障碍缺陷修复方案，修复搜索竞态、账本全量加载、报表和周期建议主线程聚合、金额输入静默失败、触控目标过小、按钮语义不足、对比度和 Reduce Motion 适配等问题，同时保留已经闭环的主导航、引导页和快速记账成功页行为。

## 影响文件

- `FlashCount/Core/MoneyValidation.swift`
- `FlashCount/Core/DesignSystem.swift`
- `FlashCount/Services/FinanceServices/LedgerQueryService.swift`
- `FlashCount/Services/FinanceServices/LedgerSearchDebounce.swift`
- `FlashCount/Services/FinanceServices/ReportAnalytics.swift`
- `FlashCount/Services/FinanceServices/RecurringSuggestionService.swift`
- `FlashCount/Services/BudgetServices/ReportBudgetSnapshotService.swift`
- `FlashCount/Views/Ledger/LedgerView.swift`、`CalendarView.swift`、`FilterSheetView.swift`、`EditTransactionView.swift`、`LedgerComponents.swift`
- `FlashCount/Views/Report/ReportView.swift`
- `FlashCount/Views/Recurring/RecurringRulesView.swift`、`AddRecurringRuleView.swift`
- `FlashCount/Views/QuickEntry/QuickEntryView.swift`、`QuickEntryControls.swift`
- `FlashCount/Services/SystemServices/PrivacyLockService.swift`、`FlashCount/Views/Reminder/ReminderView.swift`、`TemplateBarView.swift`、`Settings/CategoryManagementView.swift`
- 预算、资产、模板和分类选择相关表单/卡片视图
- `FlashCount/Views/MainTabView.swift`、`OnboardingView.swift`
- `FlashCount/Views/Components/ValidationMessage.swift`
- `FlashCountTests/MoneyValidationTests.swift`、`LedgerQueryServiceTests.swift` 及报表/周期建议回归测试
- `FlashCountUITests/FlashCountSmokeTests.swift`
- `FlashCount.xcodeproj/project.pbxproj`（由 XcodeGen 重新生成）

## 行为变化

- 搜索防抖任务保存查询快照，并在睡眠取消、查询变化或任务取消时丢弃旧结果；账本按 200 条分页，筛选条件尽量下推到 FetchDescriptor，后台查询负责总数、匹配 ID 和后续页，追加结果按交易 ID 去重。
- 报表改为 SwiftData 后台值快照、纯值类型聚合和取消/生成代号校验；刷新期间保留旧报表。周期建议改为值输入和缓存，仅在交易、规则或忽略指纹变化时重新计算。
- 统一金额校验使用 `Decimal`，拒绝空值、尾随小数点、多个小数点、指数和非法字符；各金额表单显示字段级错误、聚焦首个错误字段，并在验证完成后才修改模型和保存。
- 核心卡片和列表改用语义 `Button`，拆分主操作与暂停/菜单操作；图标按钮补充标签、提示和 identifier，关键交互保证至少 `44×44`。
- 关键数字改用 Dynamic Type 语义字体；设计系统提供浅色、深色和高对比度颜色 token；主要状态增加文字、图标或结构信息；报表、分类轮盘、快速记账、Tab、删除和筛选动画遵守 Reduce Motion。
- 主导航保持常驻，引导页继续可滚动，快速记账成功页不再自动关闭，并新增相应回归覆盖。

## 验证

- `xcodegen generate`：通过。
- `xcodebuild ... -configuration Debug build CODE_SIGNING_ALLOWED=NO`：通过（iPhone 17 模拟器）。
- `xcodebuild ... -only-testing:FlashCountTests ...`：119 项测试通过，0 失败。
- 定向 UI 测试通过：主 Tab 空闲后仍可用、引导页滚动、快速记账数字键、成功页超过 2 秒仍保留两个操作、报表周期切换，共 5 项；使用正确的单测试目标在 iPhone Air 模拟器上全部通过。
- `git diff --check`：通过。

## 限制

- 完整 UI 测试套件未在本批次跑完；旧模拟器数据存储会产生 `Cannot use staged migration with an unknown model version`，完整 runner 也曾因模拟器测试进程挂起而被中断。已在干净模拟器上完成上述 5 项定向验证。
- 报表页面仍通过主线程 `@Query` 的轻量摘要触发数据变化，实际 SwiftData 读取和聚合已移至后台 actor；账本文本/分类过滤在 actor 内扫描匹配范围后再分页，尚未实现全文索引。
- 尚未在本环境使用 Instruments 对 5,000/10,000 笔数据进行正式性能基准；本批次已加入分页、快照、取消和纯计算单元覆盖。
- 未改变本地数据格式、报表区间、周期建议识别阈值、隐私策略或网络行为。
