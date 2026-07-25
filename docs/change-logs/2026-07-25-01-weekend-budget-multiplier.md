# 周末预算倍率

## 目的

让用户可以在预算设置中提高周末的每日消费额度，同时保持整个发薪周期的预算上限不变。

## 受影响文件

- `FlashCount/Services/BudgetServices/WeekendBudgetPreferences.swift`：新增本地持久化的周末倍率选项与校验。
- `FlashCount/Services/BudgetServices/BudgetAnalyzer.swift`：按剩余日期权重重新分配每日额度。
- `FlashCount/Services/BudgetServices/BudgetReminderService.swift`、`CategoryBudgetService.swift`、`ReportBudgetSnapshotService.swift`：将周末倍率传递到提醒、分类预算和报表预算分析。
- `FlashCount/Views/Settings/SettingsView.swift`：新增周末额度设置项，支持 1.5 倍和 2 倍，默认 1.5 倍。
- `FlashCount/Views/Budget/BudgetView.swift`、`BudgetComponents.swift`、`CategoryBudgetsView.swift`、`LedgerView.swift`、`QuickEntryView.swift`、`ReportView.swift`：统一读取设置并展示调整后的额度。
- `FlashCountTests/FinanceDomainTests.swift`：新增周末倍率、周期总额保持不变及选项校验测试。
- `FlashCount.xcodeproj/project.pbxproj`：由 XcodeGen 重新生成以纳入新增 Swift 文件；`project.yml` 未手工修改。

## 行为变化

- 设置路径为“设置 > 预算周期 > 周末额度”，可选 `1.5 倍` 或 `2 倍`。
- 周末额度按所选倍率相对于工作日提高，工作日额度自动回调；剩余预算会按加权后的剩余天数分配，周期预算上限与已记录消费不变。
- 总预算页、分类预算、账本提醒、快捷记账后的提醒和报表中的预算分析均使用同一倍率。
- 设置仅保存在本机 `UserDefaults`，没有新增网络依赖、数据模型或迁移。

## 验证

- `xcodegen generate` 成功。
- iOS Simulator 通用构建成功，且关闭代码签名。
- `FlashCountTests` 全量测试通过：91 个测试、0 个失败。
- 周末倍率专项测试覆盖 1.5 倍、2 倍和周期额度守恒。

## 剩余限制

- 当前只提供 1.5 倍和 2 倍两个档位；如需自定义倍率，需要扩展选项枚举和设置界面。
- 本批次未新增 UI 自动化或截图验证；核心计算和全量单元测试已覆盖。
