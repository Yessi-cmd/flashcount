# 暖瓷分类圆盘重构

## 目的

重做记账分类的子类圆盘，改善旧实现扁平、缺少空间连续性和多层 SwiftUI Shape 重绘带来的交互质感与性能问题，同时保留短按打开、点按选择和按住滑选的操作方式。

## 影响文件

- `FlashCount/Views/Components/CategoryPickerComponents.swift`
- `FlashCount/Views/QuickEntry/QuickEntryView.swift`
- `FlashCount/Views/Ledger/EditTransactionView.swift`
- `FlashCount/Views/Recurring/AddRecurringRuleView.swift`
- `FlashCountTests/CategoryWheelLayoutTests.swift`
- `FlashCount.xcodeproj/project.pbxproj`（由 XcodeGen 重新生成）
- `docs/category-wheel-screenshots/`

## 行为变化

- 分类入口会记录自身屏幕位置，圆盘以来源位置、缩放和轻微旋转组合展开，关闭时沿相反方向收回。
- 圆盘改用单个 `Canvas` 绘制暖瓷盘面、扇区、内外圈和状态高亮，图标与文字保留为轻量 SwiftUI 覆盖层。
- 3–5、6–7、8–9 个小类分别采用不同直径、内圈比例和扇区间距，减少少量分类空旷或九项分类拥挤的问题。
- 滑动只在跨越扇区时更新状态并触发触感；松手或点按后播放短促选中反馈，再通过展示状态机完成关闭和回调。
- 快速记账、编辑账单和周期账单统一使用新圆盘；分类、预算覆盖和数据保存逻辑不变。
- 开启减少动态效果时只保留短淡入淡出；无障碍字号会改用可滚动分类列表，并继续支持 VoiceOver 选择与 Escape 关闭。
- Debug 视觉参数支持 `-visualCategoryMenuReview=<大类名称>`，用于固定展示不同密度的分类圆盘。

## 验证

- 使用 iPhone 17 Pro（iOS 26.2）模拟器检查餐饮 9 项、旅行 6 项和 AI 3 项浅色圆盘，并保存回归截图。
- 人工检查餐饮圆盘深色模式以及 Accessibility Large 字号下的滚动列表降级。
- 执行 Debug 模拟器构建，构建通过。
- 执行 Release 模拟器构建，构建通过。
- 执行 `xcodebuild test`，19 项测试通过，包含 5 项新增圆盘几何与命中测试。
- 执行 `git diff --check`，未发现空白字符错误。

## 剩余限制

- 模拟器命令行没有稳定的触摸注入接口，因此未自动化完成 20 轮“打开—滑选—关闭”的 Animation Hitches 采样；当前已通过单层 Canvas、离散索引更新和 Release 构建降低风险，仍建议发布前在真机用 Instruments 做最终连续手势采样。
- 超大无障碍字号使用列表而不是圆盘，以确保完整标签和可滚动触控目标；这是有意的可访问性降级。
