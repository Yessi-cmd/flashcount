# 报表刷新查询范围优化

## 目的

减少报表页为监听数据变化而遍历全部历史交易的刷新成本。

## 影响文件

- `FlashCount/Views/Report/ReportView.swift`

## 行为变化

- 报表刷新摘要仅观察最近 90 天交易；周报和月报的实际计算仍由报表服务按对应日期范围精确读取，因此统计范围不变。
- 新增或修改当前周/月交易时，报表继续自动刷新；超过 90 天的历史交易变化不会触发当前周期报表的无效重算。

## 验证

- 执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`，构建成功。
- 在 iPhone 17 Pro 模拟器执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -destination 'platform=iOS Simulator,id=02222C1D-48B3-490A-A9A8-FDC193410982' test CODE_SIGNING_ALLOWED=NO`，3 个领域测试全部通过。

## 剩余限制

- 报表统计仍在主线程生成；下一阶段应将值类型快照的汇总计算迁移至专用执行器。
