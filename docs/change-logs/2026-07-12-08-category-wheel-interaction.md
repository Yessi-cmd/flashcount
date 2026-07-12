# 分类圆盘交互反馈优化

## 目的

让快速记账和编辑记录中的分类圆盘提供更接近 iOS 原生控件的按压、展开、拖动和确认反馈，同时避免手势竞争或无效拖动导致的误选。

## 影响文件

- `FlashCount/Core/ErrorHandling.swift`
- `FlashCount/Views/Components/CategoryPickerComponents.swift`
- `FlashCount/Views/Components/CategoryWheelLayout.swift`
- `FlashCount/Views/QuickEntry/QuickEntryView.swift`
- `FlashCount/Views/Ledger/EditTransactionView.swift`
- `FlashCount/Views/Recurring/AddRecurringRuleView.swift`
- `FlashCountTests/CategoryWheelLayoutTests.swift`
- `FlashCountUITests/FlashCountSmokeTests.swift`

## 行为变化

- 分类格子改用原生 `Button` 按压状态；有子分类时轻点直接打开圆盘，不再以与轻点重复的长按手势触发。
- 圆盘在开启动画完成前不会接收拨选输入；展开和收起使用更短、更稳定的来源位置过渡，不再旋转。
- 拨选状态会在进入、跨越和离开扇区时准确更新，离开有效扇区后不会保留临时高亮；松手仅在有效扇区内确认。
- 圆盘使用预热且复用的触觉生成器：打开为轻触、跨扇区为选择反馈、确认分类或大类为中等冲击反馈。
- 快速记账、编辑记录和复用同一分类组件的周期账单表单使用一致的圆盘交互；无障碍字号下的列表选择与“减少动态效果”降级逻辑保持不变。

## 验证

- 运行 `xcodegen generate`，根据 `project.yml` 重新生成 Xcode 项目。
- 运行 `xcodebuild test -project FlashCount.xcodeproj -scheme FlashCount -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO`，通过全部单元测试与 UI 测试。
- 新增拨选状态单元测试，覆盖进入扇区、跨扇区、离开圆盘中心和重置；新增快速记账圆盘打开、取消及子类回填 UI 冒烟测试。
- 在 iPhone 17 Pro 模拟器检查浅色与深色模式的餐饮 9 项分类圆盘；确认标签、选中态、背景遮罩与圆盘边缘均正常。
- 运行 `git diff --check`，未发现空白字符错误。

## 剩余限制

- 触觉的时序依赖真实设备马达，模拟器只能验证调用路径和视觉状态，无法评估实际震感强度。
- 真实手指连续拖动的细微手感仍应在真机上做最终主观确认。
