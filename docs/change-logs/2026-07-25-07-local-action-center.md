# 本地行动中心

## 目的

在账本页增加本地行动中心入口，集中展示当前主账本中需要处理的预算风险、近期周期扣款、逾期待补账、分期到期、周期支出建议和未完成提醒，并直达现有管理页面。

## 影响文件

- `FlashCount/Services/FinanceServices/LocalActionCenterService.swift`
- `FlashCount/Services/FinanceServices/PayCycleService.swift`
- `FlashCount/Services/BudgetServices/BudgetReminderService.swift`
- `FlashCount/Services/BudgetServices/ReportBudgetSnapshotService.swift`
- `FlashCount/Views/ActionCenter/ActionCenterView.swift`
- `FlashCount/Views/ActionCenter/ActionCenterItemRow.swift`
- `FlashCount/Views/ActionCenter/ActionCenterSectionView.swift`
- `FlashCount/Views/ActionCenter/ActionCenterSummaryView.swift`
- `FlashCount/Views/Ledger/LedgerView.swift`
- `FlashCount/FlashCountApp.swift`
- `FlashCountTests/LocalActionCenterServiceTests.swift`
- `FlashCountUITests/FlashCountSmokeTests.swift`
- `FlashCount.xcodeproj/project.pbxproj`（由 XcodeGen 重新生成）

## 行为变化

- 账本页工具栏新增 `bolt.badge.clock` 本地行动中心入口，使用大尺寸 Sheet 展示。
- 新增只读聚合服务，固定按预算风险、近期扣款、分期到期、周期建议、未完成提醒排序，并对每组事项按逾期/紧急程度、日期和标题稳定排序。
- 周期扣款复用现金流预测，排除收入和日常消费估算；逾期待补账由周期发生项预览补充，已解决发生项不会重复展示。
- 分期事项使用 `paymentAmount(forInstallment:)`，尾期金额保持准确；锁定隐私金额时分期金额显示为 `****`。
- 周期建议读取现有本地忽略指纹，提醒仅收录未完成事项，预算仅在危险等级展示并区分实际超支与预计超支。
- 事项点击打开现有预算、周期规则、分期账单或提醒管理页，不新增 SwiftData 模型、底部 Tab、网络请求或行动中心写入逻辑。
- Debug 构建支持 `-uiTestActionCenter` 本地数据种子，仅用于 UI 测试，不进入生产行为。

## 验证

- `xcodegen generate`：通过。
- `xcodebuild ... build CODE_SIGNING_ALLOWED=NO`：通过。
- `xcodebuild ... -only-testing:FlashCountTests test CODE_SIGNING_ALLOWED=NO`：108 个测试通过。
- 行动中心 UI 用例单独运行：通过；在干净 iPhone 16e Simulator 的完整 UI 套件中行动中心用例也通过。
- 完整 UI 套件在干净 iPhone 16e Simulator 中为 15/16 通过；剩余失败为既有的 `testMainTabBarSelectionKeepsControlsAligned` 标签栏对齐用例，与本功能无关，未修改该用例或其业务代码。
- `git diff --check`：通过。

## 限制

- 首版只打开对应管理页面，不定位到具体记录，也不在行动中心内执行补账、完成提醒或其他写入操作。
- 仍使用当前单一“生活”主账本口径，没有增加账本选择器。
- 不包含推送通知、后台刷新、深链或新的持久化状态。
