# 极速记账查询范围优化

## 目的

降低极速记账页因加载全部历史交易而产生的首屏和分类推荐开销。

## 影响文件

- `FlashCount/Views/QuickEntry/QuickEntryView.swift`

## 行为变化

- 最近分类仅从最近 90 天交易中生成，保留原有收支类型、根分类去重和最多 8 项的展示规则。
- 保存支出后，预算提醒改为精确查询该笔交易所属发薪周期的交易，不再依赖完整历史交易数组；历史补录仍按该笔交易对应周期计算预算提醒。

## 验证

- 执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`，构建成功。
- 在 iPhone 17 Pro 模拟器执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -destination 'platform=iOS Simulator,id=02222C1D-48B3-490A-A9A8-FDC193410982' test CODE_SIGNING_ALLOWED=NO`，3 个领域测试全部通过。

## 剩余限制

- 若用户在 90 天内没有交易，最近分类会继续回退到默认分类；不会尝试扫描更早历史。
- 尚未建立极速记账首屏耗时的自动化基准。
