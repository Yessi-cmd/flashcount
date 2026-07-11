# 账本渐进渲染优化

## 目的

避免账本筛选结果很大时一次性构建全部交易行，改善首屏与滚动流畅度。

## 影响文件

- `FlashCount/Views/Ledger/LedgerView.swift`

## 行为变化

- 账本列表默认渲染最近 200 笔匹配交易，并在底部提供“继续加载”操作与已显示数量。
- 筛选、搜索、自定义日期或金额条件变化时，列表自动重置为首批 200 笔。
- 月度摘要、每日净额、隐私状态、批量全选和批量删除继续基于完整筛选结果，统计与批处理范围不受分页影响。
- 同时更新筛选变化监听为 iOS 17 推荐写法，移除编译弃用警告。

## 验证

- 执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`，构建成功且无警告。
- 在 iPhone 17 Pro 模拟器执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -destination 'platform=iOS Simulator,id=02222C1D-48B3-490A-A9A8-FDC193410982' test CODE_SIGNING_ALLOWED=NO`，3 个领域测试全部通过。

## 剩余限制

- 筛选阶段仍需扫描当前 SwiftData 查询返回的交易集合；后续可将更多筛选条件下推到持久化查询层。
- 尚未通过专门的万级数据自动化基准测量首屏与加载更多的耗时。
