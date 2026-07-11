# 账本展示快照性能优化

## 目的

降低账本主页面在搜索、筛选、批量选择和列表渲染时对全部交易记录的重复筛选、分组与统计开销。

## 影响文件

- `FlashCount/Views/Ledger/LedgerView.swift`
- `FlashCount/Core/Extensions.swift`

## 行为变化

- 引入账本展示快照，在一次遍历中完成日期、类型、分类、金额、关键词筛选，以及月度收入/支出统计、按日交易分组、每日净额和隐私状态计算。
- 月度摘要、交易列表、批量全选和批量删除共用同一个展示快照，保留原有筛选语义、隐私遮罩和交易排序。
- 每日列表头不再在视图渲染时重复 `reduce` 与 `contains` 计算合计和隐私状态。
- 交易列表的大额金额会自动切换为“万 / 亿 / 科学记数法”紧凑显示，避免金额文本换行挤压行布局；完整金额仍在详情场景保留。

## 验证

- 执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`，构建成功。
- 在 iPhone 17 Pro 模拟器执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -destination 'platform=iOS Simulator,id=02222C1D-48B3-490A-A9A8-FDC193410982' test CODE_SIGNING_ALLOWED=NO`，3 个领域测试全部通过。
- 在 iPhone 17 Pro 模拟器启动 App 并检查账本首屏，确认摘要卡片、列表和底部栏正确渲染；修复了抽查中发现的极大金额换行问题。

## 剩余限制

- 展示快照仍在视图重算时生成；后续可进一步引入可观察的查询状态或按日期分页，以改善万级交易规模的筛选响应。
- 尚未建立专门的账本性能基准测试数据集。
