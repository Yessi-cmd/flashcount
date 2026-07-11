# 预算页查询范围优化

## 目的

降低预算页为计算当前发薪周期预算而加载完整历史交易的开销。

## 影响文件

- `FlashCount/Views/Budget/BudgetView.swift`

## 行为变化

- 预算页仅观察最近 90 天交易；当前发薪周期最长不超过 31 天，预算余额、预警与预测的计算范围保持不变。
- 当前周期内的新增、编辑交易仍会驱动预算页面自动刷新。

## 验证

- 执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`，构建成功。
- 在 iPhone 17 Pro 模拟器执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -destination 'platform=iOS Simulator,id=02222C1D-48B3-490A-A9A8-FDC193410982' test CODE_SIGNING_ALLOWED=NO`，3 个领域测试全部通过。

## 剩余限制

- 若设备日期被人为回拨超过 90 天，需重新创建预算页才能按新的当前周期构造查询范围。
