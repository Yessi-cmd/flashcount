# 标签反馈降载与首页收入默认隐藏

## 目的

进一步降低 ProMotion 设备的标签切换动画成本，并让首页收入数据默认保持隐藏。

## 影响文件

- `FlashCount/Views/MainTabView.swift`
- `FlashCount/Views/Ledger/LedgerView.swift`
- `FlashCount/Views/Ledger/CalendarView.swift`

## 行为变化

- 移除标签选中胶囊的 `matchedGeometryEffect` 和底栏级动画环境，避免跨视图布局计算。
- 标签页面继续即时切换；每个标签按钮仅对自身胶囊透明度、缩放、图标和文字颜色执行 0.16 秒局部动画。
- 新增 `hideHomeIncome` 本地偏好，首次使用默认开启；月度卡片右上角可切换显示/隐藏。
- 隐藏状态覆盖月度收入、结余、包含收入的每日净额、收入交易金额，以及账本日历中的收入、结余和当日合计。
- 支出金额和支出交易保持可见；原有受隐私锁保护的工资收入仍遵循解锁规则。

## 验证

- 执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`，构建成功。
- 在 iPhone 17 Pro 模拟器执行 `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -destination 'platform=iOS Simulator,id=02222C1D-48B3-490A-A9A8-FDC193410982' test CODE_SIGNING_ALLOWED=NO`，3 个领域测试全部通过。
- 在模拟器显式开启 `hideHomeIncome` 并截图检查：月度收入、结余、日合计及收入交易金额均显示为 `****`，支出保持可见。

## 剩余限制

- 模拟器无法复现 iPhone 16 Pro Max 的 120Hz 显示链路，标签切换最终体感仍需真机复测。
- 当前没有 UI 自动化用例验证普通收入行的遮罩与显隐按钮点击；已通过代码路径和运行态隐私收入样本检查。
