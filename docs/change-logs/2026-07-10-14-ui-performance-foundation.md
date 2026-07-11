# UI 与流畅度基础优化

## 目的

建立更清晰的视觉层级与统一的轻触动效，并减少账本、报表在刷新时的重复分配和重复遍历，为后续页面级改造提供基础。

## 影响文件

- `FlashCount/Core/DesignSystem.swift`
- `FlashCount/Core/Extensions.swift`
- `FlashCount/Views/MainTabView.swift`
- `FlashCount/Views/QuickEntry/QuickEntryView.swift`
- `FlashCount/Views/Ledger/LedgerView.swift`
- `FlashCount/Views/Asset/AssetDashboardView.swift`
- `FlashCount/Views/Budget/BudgetComponents.swift`
- `FlashCount/Views/Report/ReportView.swift`
- `FlashCount/Services/FinanceServices/ReportService.swift`
- `FlashCount/Views/Settings/SettingsView.swift`
- `FlashCount/Services/FinanceServices/PayCycleService.swift`
- `FlashCountTests/FinanceDomainTests.swift`

## 行为变化

- 设计系统新增统一间距、圆角、动效、摘要卡片和按压反馈；普通内容卡片降低阴影强度，减少视觉与合成负担。
- 底部导航和数字键盘提供一致的按压反馈，并尊重“减少动态效果”。
- 极速记账页的数字键盘与保存按钮固定在底部安全区，输入金额时不再需要滚动至页面末尾。
- 账本月度概览改为高层级摘要卡片，并在一次遍历中完成收入、支出与隐私收入状态计算；交易分组在单次列表渲染中复用。
- 资产首页在单次页面渲染内构建汇总快照，所有资产、负债、资金池、分期与储蓄卡片共享结果，避免重复过滤同一批数据；净资产升级为摘要卡片。
- 预算概览使用摘要卡片，并在“减少动态效果”开启时停用进度条弹簧动画。
- 金额、日期格式器改为共享实例，避免交易列表滚动时反复创建格式器。
- 报表刷新改为整数摘要，替代拼接全部交易的长字符串；每日消费聚合改为按日期单次累计。
- 报表页将周期收支摘要升级为带状态提示的 Hero 区域，周期切换与数据刷新尊重“减少动态效果”。
- 修复报表和设置页原有的字符串插值转义错误，使工程重新可编译。
- 发薪周期服务可注入日历，确保日期边界计算与调用方时区一致，并使跨时区单测稳定。

## 验证

- 执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`，构建成功。
- 在 iPhone 17 Pro 模拟器执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -destination 'platform=iOS Simulator,id=02222C1D-48B3-490A-A9A8-FDC193410982' test CODE_SIGNING_ALLOWED=NO`，3 个领域测试全部通过。

## 剩余限制

- 尚未在真机或 Instruments 中测量实际帧率、首屏耗时与大数据量滚动表现。
- 报表生成仍运行在主线程；后续应将数据快照与统计迁移至专用模型执行器。
