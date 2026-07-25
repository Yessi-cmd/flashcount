# 周末预算提醒视觉收敛

## 目的

减少周末预算提醒中的长说明文字，避免提醒卡片被撑高，同时保留用户能识别周末额度状态的视觉提示。

## 受影响文件

- `FlashCount/Services/BudgetServices/BudgetAnalyzer.swift`、`BudgetReminderService.swift`：移除“周末按 X 倍额度分配”附加文案，新增周末额度状态标记。
- `FlashCount/Core/DesignSystem.swift`：新增周末提示色。
- `FlashCount/Views/Ledger/LedgerView.swift`、`FlashCount/Views/Budget/BudgetComponents.swift`：为周末额度添加紧凑的日历角标、边框色和额度色；提醒正文恢复紧凑排版。
- `FlashCountTests/FinanceDomainTests.swift`：验证周末状态仍可识别且提醒文案不再包含长说明。

## 行为变化

- 主页日常预算提醒不再追加“周末按 1.5 倍额度分配”等第二行文字。
- 周末状态通过蓝灰色提示色和日历角标表达，原有健康/警告/危险图标仍保留其语义颜色。
- 预算页的“今日可花”额度在周末使用同一提示色和日历图标；预算计算逻辑不变。

## 验证

- `git diff --check` 通过。
- 已补充周末状态及文案收敛的单元测试。
- iOS Simulator 构建成功。
- `FlashCountTests` 全量测试通过：91 个测试、0 个失败。

## 剩余限制

- 本批次未加入 UI 自动化截图比对；视觉变化通过紧凑布局、统一设计色和构建/单元测试覆盖。
