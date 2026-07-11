# 分类轮盘拨动反馈

## 目的

让子类轮盘具备类似机械拨轮的连续刻度感，提升盲操作确认感与交互质感。

## 影响文件

- `FlashCount/Views/Components/CategoryPickerComponents.swift`
- `docs/change-logs/2026-07-11-06-category-wheel-haptics.md`

## 行为变化

- 手指在轮盘外圈滑动时，根据触点角度实时识别当前子类扇区。
- 每次跨入不同扇区触发一次轻量选择振动，停留在同一扇区时不会重复振动。
- 当前经过的扇区会同步加强底色、描边并轻微放大图标文字。
- 松手后直接选择当前子类，支持一次按住、拨动、松手完成选择。
- 普通点按扇区同样通过零距离拨动手势完成选择和反馈。
- 中心大类按钮与 VoiceOver 选择行为保持不变。

## 验证

- `git diff --check -- FlashCount/Views/Components/CategoryPickerComponents.swift` 通过。
- `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` 构建通过。

## 剩余限制

- iOS 模拟器无法验证真实 Taptic Engine 强度，最终振动手感需在真机确认。
