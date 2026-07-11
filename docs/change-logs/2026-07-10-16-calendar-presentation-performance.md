# 日历展示快照性能优化

## 目的

减少日历页面为日格、月度汇总和选中日期详情重复扫描全部交易记录的开销。

## 影响文件

- `FlashCount/Views/Ledger/CalendarView.swift`

## 行为变化

- 新增当月展示快照，在单次按月遍历中生成每日收入、支出、净额、隐私收入标记和交易列表。
- 日历格、月度汇总、选中日期明细共享同一快照，维持原有隐私遮罩、排序和金额展示逻辑。
- 去除日历渲染中多次按月过滤、按日 `contains` 和重复汇总的计算。

## 验证

- 执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`，构建成功。
- 在 iPhone 17 Pro 模拟器执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -destination 'platform=iOS Simulator,id=02222C1D-48B3-490A-A9A8-FDC193410982' test CODE_SIGNING_ALLOWED=NO`，3 个领域测试全部通过。

## 剩余限制

- 日历仍需从 SwiftData 查询结果中定位当前月份；后续可将月份范围下推到查询层，进一步改善超大交易数据集的切月速度。
