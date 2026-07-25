# 本地数据健康中心

## 目的

在设置页增加“本地数据健康中心”，让用户可以在设备本地只读扫描数据异常，查看修复预览后再一次性提交安全修复。

## 影响文件

- `FlashCount/Services/DataServices/DataHealthIssueKind.swift`
- `FlashCount/Services/DataServices/DataHealthFinding.swift`
- `FlashCount/Services/DataServices/DataHealthRepairPlan.swift`
- `FlashCount/Services/DataServices/DataHealthReport.swift`
- `FlashCount/Services/DataServices/DataHealthService.swift`
- `FlashCount/Views/Settings/DataHealthCenterView.swift`
- `FlashCount/Views/Settings/DataHealthFindingRow.swift`
- `FlashCount/Views/Settings/DataHealthRepairPreviewView.swift`
- `FlashCount/Views/Settings/SettingsView.swift`
- `FlashCount/Core/ErrorHandling.swift`
- `FlashCountTests/DataHealthServiceTests.swift`
- `FlashCountUITests/FlashCountSmokeTests.swift`
- `FlashCount.xcodeproj/project.pbxproj`（由 XcodeGen 根据现有 `project.yml` 重新生成）

## 行为变化

- 设置页原有的即时“数据自检修复”入口改为“本地数据健康中心”，进入后自动扫描。
- 扫描覆盖重复 UUID、孤儿预算、空交易 `cashPoolDelta`、重复资金池状态、缺失账本、未分类交易和无效交易金额。
- 扫描阶段不写入数据；可修复问题会生成预览，用户确认后才执行。
- 修复在一次 SwiftData 保存中提交，失败时回滚；重复资金池状态只保留最近更新的记录，不累加历史重复值。
- 对存在原始 ID 引用歧义的重复 UUID、孤儿预算、未分类交易、无效金额和无法判断是否已包含人工资金池校准的问题，仅提示人工处理。
- 移除旧的 `DataRepairService` 实现，避免两个修复入口产生不同规则。

## 验证

- `xcodegen generate`
- iOS 通用设备 Debug 构建（关闭代码签名）
- `DataHealthServiceTests`：扫描只读、空 delta 修复、资金池状态合并、孤儿预算保护、重复 UUID 人工审查、可安全重编号和预览过期保护
- `FlashCountSmokeTests/testDataHealthCenterScansFromSettings`
- 全量测试：103 个单元测试、15 个 UI 测试全部通过

## 目前限制

- 扫描不会替用户猜测孤儿预算应归属的分类，也不会自动修正未分类交易或非正金额。
- 如果资金池状态与交易投影的差异无法证明来自未记录的交易 delta，系统会保留现状并要求人工确认。
