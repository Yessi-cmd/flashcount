# 日历月份查询下推

## 目的

将日历页面的月份过滤从内存层下推到 SwiftData，避免打开或切换日历时加载完整历史交易。

## 影响文件

- `FlashCount/Views/Ledger/CalendarView.swift`

## 行为变化

- 月份导航保留在轻量父视图中；当月内容由独立子视图按月创建 SwiftData 查询，仅读取展示月份内的交易。
- 切换月份时重建查询并清除日期选择，日格、月度收支、隐私遮罩和当日交易明细保持原有行为。
- 当月展示快照不再进行二次月份过滤，直接基于查询结果生成。

## 验证

- 执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`，构建成功。
- 在 iPhone 17 Pro 模拟器执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -destination 'platform=iOS Simulator,id=02222C1D-48B3-490A-A9A8-FDC193410982' test CODE_SIGNING_ALLOWED=NO`，3 个领域测试全部通过。

## 剩余限制

- 日历切换月份仍会创建新的 SwiftUI 子视图以更新查询；这是保证动态 `@Query` 谓词更新的显式策略。
- 尚未针对跨多年历史数据建立日历切月耗时基准。
