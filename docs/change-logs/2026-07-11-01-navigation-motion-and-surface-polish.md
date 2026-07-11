# 主导航动效与表面质感升级

## 目的

修复底部标签栏分割线覆盖悬浮记账加号的问题，并让主导航、页面切换和极速记账的视觉与交互质感产生更明显变化。

## 影响文件

- `FlashCount/Core/DesignSystem.swift`
- `FlashCount/Views/MainTabView.swift`
- `FlashCount/Views/QuickEntry/QuickEntryView.swift`
- `FlashCount/Views/Ledger/LedgerView.swift`
- `FlashCount/Views/Budget/BudgetView.swift`
- `FlashCount/Views/Report/ReportView.swift`
- `FlashCount/Views/Asset/AssetDashboardView.swift`

## 行为变化

- 底栏分割高光从顶层 `overlay` 移入背景层，不再穿过或覆盖主记账加号。
- 主加号增加实体外圈、边缘高光、双层阴影和按压缩放/旋转反馈，强化悬浮层级。
- 标签选中胶囊使用 `matchedGeometryEffect` 在栏目间平滑移动；标签切换增加轻触反馈与页面轻微缩放、位移和透明度过渡。
- 极速记账的收支切换块使用匹配几何动画，页面区块和固定数字键盘按层级依次进入，成功反馈使用缩放与淡入组合转场。
- 新增静态环境光背景；普通卡片与 Hero 卡片加入渐变边缘高光和双层阴影，提升层次但不使用持续重型动画。
- 新增动效均遵循系统“减少动态效果”设置。

## 验证

- 执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`，构建成功且无警告。
- 在 iPhone 17 Pro 模拟器启动 App 并截图检查账本首屏，确认悬浮加号外圈完整且分割线位于按钮下层。
- 在 iPhone 17 Pro 模拟器执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -destination 'platform=iOS Simulator,id=02222C1D-48B3-490A-A9A8-FDC193410982' test CODE_SIGNING_ALLOWED=NO`，3 个领域测试全部通过。

## 剩余限制

- 静态截图无法完整呈现匹配几何、按压和页面进入动画，仍建议在真机上确认触感强度与动画节奏。
- 当前自动化测试覆盖财务领域逻辑，尚未包含 UI 动画断言。
