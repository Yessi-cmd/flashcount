# iOS 26 快速记账玻璃键盘布局修复

## 目的

修复 iOS 26 原生 Glass 按钮额外内边距导致快速记账键盘整体变高、遮挡分类卡片的问题，同时保留原生玻璃触控反馈与较早系统的既有布局。

## 影响文件

- `FlashCount/Views/QuickEntry/QuickEntryControls.swift`
- `FlashCount/Views/QuickEntry/QuickEntryView.swift`
- `FlashCountUITests/FlashCountSmokeTests.swift`
- `docs/change-logs/2026-07-15-04-quick-entry-glass-layout.md`

## 行为变化

- iOS 26 数字键和保存按钮缩短内部标签高度，抵消系统 Glass 样式附加的外层内边距，使整块键盘回到原有布局预算内。
- 高度较大的键盘继续使用安全区 inset 预留独立空间，并增加实体底层隔离滚动内容，不再通过 `safeAreaBar` 让分类内容透到按键下方。
- UI 回归测试新增分类控制区与首排键盘不得相交的几何断言，同时继续验证数字键可点击并能启用保存按钮。
- iOS 17–25 的数字键和保存按钮高度保持不变。

## 验证

- 在 iPhone 17 Pro（iOS 26.2）模拟器分别使用标准字号与辅助功能大字号检查首屏；确认标准字号可完整显示两排常用分类和控制条，大字号下滚动后全部分类可完整移到键盘上方，按键与文字无裁切或透叠。
- 定向执行 `testQuickEntryNumberKeyEnablesSave`，几何防遮挡断言、数字输入和保存按钮状态均通过。
- 执行完整测试套件，共 82 条测试全部通过，其中 7 条 UI 测试、75 条单元测试。
- `git diff --check` 通过。

## 剩余限制

- 极端辅助功能字号下，模板条和分类内容仍可能需要滚动查看；键盘本身保持固定的高频输入布局，不随文字字号无限增高。
