# 全局应用柔和克制视觉方向

## 目的

将视觉探索中选定的 B 方向“柔和但不幼稚”应用到正式界面，在不改动记账、预算、资产、报表与持久化逻辑的前提下，统一颜色、层级、组件边界和交互反馈，并让主界面的核心财务信息优先于筛选工具出现。

## 影响文件

- `FlashCount/Core/DesignSystem.swift`
- `FlashCount/FlashCountApp.swift`
- `FlashCount/Models/Ledger.swift`
- `FlashCount/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`
- `FlashCount/Services/FinanceServices/ReportService.swift`
- `FlashCount/Views/Asset/AssetDashboardView.swift`
- `FlashCount/Views/Asset/InstallmentBillView.swift`
- `FlashCount/Views/Asset/PhysicalAssetView.swift`
- `FlashCount/Views/Asset/SavingsGoalView.swift`
- `FlashCount/Views/Budget/BudgetComponents.swift`
- `FlashCount/Views/Budget/BudgetView.swift`
- `FlashCount/Views/Components/CategoryPickerComponents.swift`
- `FlashCount/Views/Ledger/LedgerView.swift`
- `FlashCount/Views/MainTabView.swift`
- `FlashCount/Views/Onboarding/OnboardingView.swift`
- `FlashCount/Views/QuickEntry/QuickEntryView.swift`
- `FlashCount/Views/Recurring/RecurringRulesView.swift`
- `FlashCount/Views/Report/ReportView.swift`
- `FlashCount/Views/Settings/SettingsView.swift`
- `FlashCountWidget/FlashCountWidget.swift`
- `docs/global-b-screenshots/`

## 行为变化

- 全局主色改为低饱和墨绿色，背景改为暖中性色；卡片使用实体背景、细边框和克制阴影，移除装饰性渐变与玻璃材质。
- 调整全局圆角、间距、文字色和语义色，让列表、卡片、按钮与状态展示共享一致的视觉规则，并同时适配浅色与深色模式。
- 主界面优先呈现本月支出、收入和结余，再展示搜索与筛选；三项数据不再使用相同视觉权重。
- 底部 Tab 栏保留并重新设计；中间“记一笔”使用紧凑的圆角矩形主操作，不再使用发光渐变圆形按钮。
- 预算、资产、分期、储蓄目标、周期规则等空状态主按钮统一为实体主色按钮。
- 报表、预算状态、分类选择和设置页减少无意义多色与 emoji 装饰，保留收支、风险和分类识别所需的语义色。
- 报表洞察文字移除 emoji 前缀，含义和计算逻辑不变。
- 新创建的默认账本使用新的品牌色；已有账本及历史数据不会被迁移或修改。
- 增加仅在 DEBUG 生效的 `-visualReviewTab` 启动参数，用于稳定截取不同正式 Tab 页面的视觉回归截图。

## 验证

- 使用 iPhone 17 Pro（iOS 26.2）模拟器构建并运行正式界面。
- 人工检查主界面、预算、报表、快速记账以及主界面深色模式截图。
- 执行 `xcodebuild test`：8 项测试通过，0 项失败。
- 执行 `git diff --check`：未发现空白字符错误。

## 剩余限制

- 收支、警告与分类身份色仍有意保留，避免为了单色统一而降低状态辨识度。
- 导航栏等系统控件继续使用当前 iOS 原生外观，因此会保留系统自身的材质表现。
- 本轮已覆盖主流程的浅色视觉与主界面深色视觉，尚未执行完整 Dynamic Type 尺寸矩阵和所有次级页面的逐页截图回归。
- Widget 源码已同步主色，但当前 `project.yml` 未包含 Widget target，本轮主 Scheme 构建未单独编译该文件。
