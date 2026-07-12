# 分类圆盘与全局字体优化

## 目的

修复 AI 分类圆盘中 `ai coding plan` 文字贴近并越过盘沿的问题，同时统一应用与快速记账主流程的字体设计、字号层级和字重，让中英文、金额与数字键盘在保持清晰的前提下更协调。

## 影响文件

- `FlashCount/Core/DesignSystem.swift`
- `FlashCount/FlashCountApp.swift`
- `FlashCount/Views/Components/CategoryWheelLayout.swift`
- `FlashCount/Views/Components/CategoryPickerComponents.swift`
- `FlashCount/Views/Components/TemplateBarView.swift`
- `FlashCount/Views/QuickEntry/QuickEntryView.swift`
- `FlashCount/Views/QuickEntry/QuickEntryControls.swift`
- `FlashCountTests/CategoryWheelLayoutTests.swift`

## 行为变化

- 全局文本环境使用系统圆体设计；中文继续使用系统 CJK 回退字体，英文、数字和金额获得更一致的圆润字形。
- 设计系统新增语义字体层级，并应用到快速记账的金额、收支切换、模板、分类标题、数字键盘、保存按钮和分类圆盘。
- 圆盘标签根据 3–5、6–7、8–9 个扇区及圆盘实际尺寸计算标签框，不再使用统一的固定宽度。
- 低密度圆盘的标签位置向盘心收拢；长英文允许两行居中、字距收紧和有限缩放，`ai coding plan` 会显示为两行并与盘沿保留安全距离。
- 选中或滑过扇区时仅轻微放大图标并将标签向内移动，不再把整段文字向盘外放大。
- 圆盘中心辅助文字从固定 9pt 改为语义辅助字号，提高可读性；超大无障碍字号仍使用原有可滚动列表。

## 验证

- 在 iPhone 17 Pro（iOS 26.2）模拟器执行完整 `xcodebuild test`：26 项单元测试和 2 项 UI 测试全部通过。
- 新增圆盘标签边界测试，覆盖 3–9 个扇区、各自首选尺寸和 250pt 紧凑尺寸；6 项圆盘几何测试全部通过。
- 在 iPhone 17 Pro 浅色模式、默认动态字体下分别检查 AI 3 项、旅行 6 项和餐饮 9 项圆盘；确认长英文正确换行，所有标签均位于盘沿内，高密度圆盘未出现文字碰撞。
- 执行 `git diff --check`，未发现空白字符错误。

## 剩余限制

- 本轮视觉回归集中在 iPhone 17 Pro 的浅色模式和默认动态字体；深色模式沿用相同几何与系统字体，但未逐页重新截图。
- 用户自定义的极长分类名称最多显示两行，空间不足时仍会缩小或截断；无障碍字号会切换到完整文字的滚动列表。
