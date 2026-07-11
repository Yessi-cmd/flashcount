# ProMotion 标签切换流畅度修复

## 目的

解决高刷新率设备切换底部标签时的掉帧问题，保留可感知但渲染成本低的导航反馈。

## 影响文件

- `FlashCount/Views/MainTabView.swift`

## 行为变化

- 移除账本、预算、报表和资产整页的透明度、缩放与位移动画，避免图表、长列表和复杂卡片参与大面积动画合成。
- 标签切换不再通过全局 `withAnimation` 修改 `selectedTab`，防止动画事务传播进入整个 `TabView` 页面树。
- 移除标签图标的 Symbol bounce，改为仅在底栏内部执行轻量缩放。
- 保留底栏选中胶囊的匹配几何移动、图标轻微缩放和触感反馈；动画作用域明确限制在底栏 `HStack`。

## 验证

- 执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`，构建成功。
- 静态检查确认 `MainTabView` 不再包含整页 `tabPageMotion`、图标 `symbolEffect` 或全局标签切换 `withAnimation`。
- 在 iPhone 17 Pro 模拟器执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -destination 'platform=iOS Simulator,id=02222C1D-48B3-490A-A9A8-FDC193410982' test CODE_SIGNING_ALLOWED=NO`，3 个领域测试全部通过。

## 剩余限制

- 模拟器无法等价验证 iPhone 16 Pro Max 的 120Hz ProMotion 帧稳定性，仍需要在真机重复快速切换四个标签确认体感。
- 当前没有基于 Core Animation Instruments 的自动化帧耗时门禁。
