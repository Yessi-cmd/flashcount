# 快捷记账路由与区域格式统一

## 目的

确保 Siri、快捷指令和 Widget 的“快速记账”入口直接进入记账页，并统一极速记账页的中文日期显示。

## 影响文件

- `FlashCount/Core/QuickAddIntent.swift`
- `FlashCount/Views/MainTabView.swift`
- `FlashCount/Views/QuickEntry/QuickEntryView.swift`

## 行为变化

- 快速记账 App Intent 写入本地路由请求；主标签页在冷启动、前台运行和首次引导结束后安全处理该请求并展示 `QuickEntryView`。
- 首次引导显示期间会保留请求，避免与引导全屏页竞争展示。
- 极速记账日期选择器使用 `zh_CN` 区域格式，避免在中文界面中显示英文月份。

## 验证

- 路由实现后执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`，构建成功。
- 在 iPhone 17 Pro 模拟器中预置快捷记账请求并启动 App，已截图确认直接展示“记一笔”页面及固定数字键盘。

## 剩余限制

- 加入中文日期区域格式后的最终构建与截图验证因本地 Codex 使用额度限制暂未完成；恢复可用后应优先补跑构建、测试与运行态截图。
