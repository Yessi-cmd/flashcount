# iOS 26 Liquid Glass 视觉与动效适配

## 目的

在保持 iOS 17–25 现有界面与本地优先行为不变的前提下，为 iOS 26 的主导航和高频记账流程采用原生 Liquid Glass 材质、交互反馈与更连贯的选择动效，同时维持财务数据卡片的清晰度和渲染效率。

## 影响文件

- `FlashCount/Core/DesignSystem.swift`
- `FlashCount/Views/MainTabView.swift`
- `FlashCount/Views/Ledger/LedgerView.swift`
- `FlashCount/Views/QuickEntry/QuickEntryControls.swift`
- `FlashCount/Views/QuickEntry/QuickEntryView.swift`
- `FlashCount/Views/Report/ReportView.swift`
- `FlashCountUITests/FlashCountSmokeTests.swift`
- `docs/change-logs/2026-07-15-03-ios26-liquid-glass.md`

## 行为变化

- iOS 26 主标签栏改用 `GlassEffectContainer` 组织五个交互式玻璃控件，选中项和中央记账入口使用品牌色 tint，并把标签选择动画限制在导航自身，避免动画事务扩散到整页。
- iOS 26 账本日期筛选、报表周期选择和报表日期导航改用统一形状与层级的原生 Glass 表面；标准导航栏与工具栏继续交给系统自动适配。
- iOS 26 极速记账的收支切换、数字键盘和保存按钮分别使用交互式 Glass、原生 `.glass` 按钮样式和 `.glassProminent` 主操作样式。
- 极速记账底部控制区在 iOS 26 使用 `safeAreaBar`，让滚动内容在玻璃键盘下方获得系统滚动边缘过渡；较早系统继续使用原有 `safeAreaInset` 和实体背景。
- 所有新增选择动画遵循“减少动态效果”；iOS 17–25 继续显示原有实体控件，不引用 iOS 26 运行时 API。
- 为数字键、金额和保存按钮增加稳定的无障碍标识，并新增 UI 回归测试，验证输入数字后金额更新且保存按钮启用。

## 验证

- 使用 Xcode 26.2 / iOS 26.2 SDK 执行无签名 Simulator 完整构建，构建成功。
- 在 iPhone 17 Pro（iOS 26.2）模拟器启动并检查账本首页、报表页和极速记账页，确认原生玻璃材质、选中 tint、系统工具栏和底部滚动边缘层级正常。
- 执行全部 7 条 `FlashCountUITests`，全部通过；覆盖主标签栏、报表导航、极速记账与分类轮盘，并确认玻璃数字键保持可点击且正确驱动保存状态。
- 执行全部 75 条 `FlashCountTests`，全部通过。

## 剩余限制

- Liquid Glass 的折射、光照响应和触控形变会随壁纸、内容和设备显示环境变化，静态截图无法完整体现；仍建议在真机上确认最终触感与透明度。
- 本次仅将 Glass 用于导航和控制层，数据摘要、列表与图表卡片刻意保留实色表面，避免降低数字可读性或增加大面积实时材质渲染负担。
