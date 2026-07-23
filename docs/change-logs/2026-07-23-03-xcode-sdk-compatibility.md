# Xcode SDK compatibility

## 目的

- 让项目能在 GitHub macOS 15 Runner 的 Xcode 16.4 上编译，同时保留 iOS 26 上的 Liquid Glass 视觉效果。

## 受影响文件

- `FlashCount/Views/Components/LiquidGlassContainer.swift`
- `FlashCount/Views/Report/ReportView.swift`
- `FlashCount/Views/QuickEntry/QuickEntryView.swift`
- `FlashCount/Views/Ledger/LedgerView.swift`

## 行为变化

- 新增跨 SDK 的 `LiquidGlassContainer`：使用支持 iOS 26 API 的编译器时采用系统 `GlassEffectContainer`，较早 SDK 则以透明容器保留相同布局和交互。
- 报表涨跌颜色判断改为显式的可选布尔比较，兼容 Xcode 16.4 的穷尽性检查。

## 验证

- 从 GitHub Actions 运行 `30017493283` 复现并定位 Xcode 16.4 的三个编译错误。
- 本地已完成 XcodeGen 工程生成；待本批提交触发远端 Xcode 16.4 完整构建与测试验证。

## 剩余限制

- 在不包含 iOS 26 Liquid Glass API 的较早 SDK 上，控件组合不会产生系统融合玻璃效果，但不会改变功能、布局或可访问性。
