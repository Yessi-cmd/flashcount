# 周期补账与现金流预测

## 目的

为周期规则增加可确认、可跳过且幂等的历史发生项补账流程，并在资产页提供本地现金流预测，避免启动时静默补账造成重复记账或资金池重复累计。

## 影响文件

- `FlashCount/Models/RecurringOccurrence.swift`：新增周期发生项模型与稳定幂等键。
- `FlashCount/Services/FinanceServices/RecurringOccurrenceService.swift`、`RecurringCatchUpPreferences.swift`：新增发生项预览、批量补账、游标推进与补账模式设置。
- `FlashCount/Services/FinanceServices/CashFlowForecastService.swift`：新增固定事项及日常趋势现金流预测。
- `FlashCount/Models/AssetModels/InstallmentBill.swift`：修正分期尾期金额，保证预测总额与账单总额一致。
- `FlashCount/Core/FlashCountSchema.swift`、`FlashCount/FlashCountApp.swift`：增加 V1→V2 轻量迁移并启用版本化容器。
- `FlashCount/Services/FinanceServices/RecurringService.swift`、`DefaultDataService.swift`：启动时登记历史周期交易，并支持自动/确认两种模式。
- `FlashCount/Services/DataServices/DataBackupService.swift`：备份、恢复发生项及补账模式，兼容旧备份。
- `FlashCount/Views/Recurring/RecurringRulesView.swift`、`RecurringBackfillView.swift`：增加待补账入口与确认界面。
- `FlashCount/Views/Asset/AssetDashboardView.swift`、`CashFlowForecastView.swift`：增加现金流预测入口、图表与事件明细。
- `FlashCount/Views/Settings/SettingsView.swift`：增加周期补账模式选择。
- `FlashCountTests/CashFlowForecastTests.swift`、`FinanceDomainTests.swift` 及相关测试模型容器：增加补账、预测、迁移与备份覆盖。
- `FlashCount.xcodeproj/project.pbxproj`：由 XcodeGen 根据现有 `project.yml` 重新生成。

## 行为变化

- 默认采用“先确认再补账”；待处理周期账在“周期账单”页面展示，用户可逐笔补账或跳过。
- 批量操作一次性写入交易、发生项、资金池累计差额和规则游标；重复提交不会生成重复交易。
- 可切换为启动自动补账，保留原有自动生成能力，但新增发生项记录用于去重和恢复。
- 资产页新增本周期、30/60/90 天现金流预测，可选择只看固定事项或叠加近 90 天日常支出趋势；预测只读本地数据，不写入账本。
- JSON 备份继续兼容旧版本，并保存新的发生项及补账偏好。

## 验证

- `xcodegen generate` 成功。
- `xcodebuild ... -only-testing:FlashCountTests test CODE_SIGNING_ALLOWED=NO`：97 项单元测试全部通过。
- `xcodebuild ... -only-testing:FlashCountUITests test CODE_SIGNING_ALLOWED=NO`：14 项 UI 冒烟测试全部通过。
- `git diff --check` 通过。

## 仍有限制

- 日常消费预测是基于最近 90 天本地历史支出的估算，不代表已确认现金流。
- 待确认的逾期周期项在用户处理前不会计入现金流预测；确认或跳过后会自动重新计算。
- 当前补账界面默认按规则金额生成交易，金额/备注的逐笔编辑能力保留在服务层接口，尚未提供独立编辑控件。
