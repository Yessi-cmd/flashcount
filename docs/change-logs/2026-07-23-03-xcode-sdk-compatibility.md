# Xcode SDK compatibility

## 目的

- 让项目能在 GitHub macOS 15 Runner 的 Xcode 16.4 上编译，同时保留 iOS 26 上的 Liquid Glass 视觉效果。

## 受影响文件

- `FlashCount/Views/Components/LiquidGlassContainer.swift`
- `FlashCount/Core/DesignSystem.swift`
- `FlashCount/Views/Report/ReportView.swift`
- `FlashCount/Views/QuickEntry/QuickEntryView.swift`
- `FlashCount/Views/QuickEntry/QuickEntryControls.swift`
- `FlashCount/Views/Ledger/LedgerView.swift`

## 行为变化

- 新增跨 SDK 的 `LiquidGlassContainer`：使用支持 iOS 26 API 的编译器时采用系统 `GlassEffectContainer`，较早 SDK 则以透明容器保留相同布局和交互。
- 快速记账的系统玻璃按钮样式仅在支持该 API 的编译器中参与编译；较早 SDK 自动采用已有的常规按钮样式。
- 共享的玻璃表面修饰器在较早 SDK 中自动退化为透明修饰器，避免缺失 `Glass` 类型时中断整个 App 模块编译。
- 报表涨跌颜色判断改为显式的可选布尔比较，兼容 Xcode 16.4 的穷尽性检查。

## 验证

- 从 GitHub Actions 运行 `30017493283` 复现并定位 Xcode 16.4 的三个编译错误。
- 本地已完成 XcodeGen 工程生成；本地 `xcodebuild build` 未报告 Swift 源码错误，仅因环境没有 Simulator runtime 而在资源编译阶段停止。
- 已从 GitHub Actions 运行 `30018155465` 定位 Xcode 16.4 中不支持的 `.glass` 和 `.glassProminent` 按钮样式；待本批提交触发远端完整构建与测试验证。
- 已从 GitHub Actions 运行 `30018738429` 定位共享玻璃表面中的 `Glass` 类型缺失；待本批提交触发远端完整构建与测试验证。

## 剩余限制

- 在不包含 iOS 26 Liquid Glass API 的较早 SDK 上，控件组合不会产生系统融合玻璃效果，但不会改变功能、布局或可访问性。
