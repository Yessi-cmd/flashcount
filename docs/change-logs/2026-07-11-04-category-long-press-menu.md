# 记账分类长按菜单质感优化

## 目的

将记账分类原有偏玩具化的放射式长按菜单，调整为层级清晰、视觉克制且更适合高刷设备的上下文选择面板。

## 影响文件

- `FlashCount/Views/Components/CategoryPickerComponents.swift`
- `docs/change-logs/2026-07-11-04-category-long-press-menu.md`

## 行为变化

- 长按分类后改为展示底部材质面板，统一呈现大类入口与全部具体分类。
- 当前选中项使用轻量底色、描边和勾选标识，不再使用悬浮徽章与大面积彩色阴影。
- 子类较多时使用可滚动列表，避免放射布局拥挤或截断。
- 移除逐项弹跳、旋转、模糊和延迟入场，仅保留整块面板的短距离位移与淡入淡出。
- 分类入口移除省略号气泡和“长按选子类”小字，改用克制的下拉提示符。
- 长按触发时间从 0.15 秒调整为 0.28 秒，减少误触；按压缩放幅度同步收敛。
- 快速记账、编辑账目和周期记账继续复用同一套分类菜单。

## 验证

- `git diff --check -- FlashCount/Views/Components/CategoryPickerComponents.swift` 通过。
- `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` 构建通过。

## 剩余限制

- 长按手感和 120Hz 真机动画仍需在实际设备上进行最终主观验收。
