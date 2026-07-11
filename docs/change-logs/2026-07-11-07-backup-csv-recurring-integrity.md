# 备份、CSV 与周期日期完整性修复

## 目的

修复替换恢复可能先清空本地数据库、CSV 导入不更新账本与资金池、备份版本未校验，以及月底周期账单经过短月份后永久漂移的问题；同时为这些高风险数据路径补充自动化回归测试。

## 受影响文件

- `FlashCount/Models/RecurringRule.swift`
- `FlashCount/Services/FinanceServices/RecurringService.swift`
- `FlashCount/Services/DataServices/DataBackupService.swift`
- `FlashCount/Services/DataServices/DefaultDataService.swift`
- `FlashCount/Services/DataServices/CSVTransactionService.swift`
- `FlashCountTests/FinanceDomainTests.swift`
- `docs/AI_PROJECT_CONTEXT.md`

## 行为变化

- 替换恢复不再先单独保存删除操作；旧数据删除、新数据导入、默认数据补齐和单账本整理现在通过同一次 `ModelContext.save()` 提交，失败时回滚上下文。
- 备份格式升级到 `1.6.0`，导入和预览会在任何数据变更前校验版本，仅接受 `1.0.0...1.6.0`。
- 周期规则备份新增可选的 `anchorDay` 和 `endDate`，继续兼容缺少这些字段的旧版 1.x 备份。
- CSV 导入为交易绑定默认账本、记录 `cashPoolDelta`、同步资金池总变化，并在同一文件内按 UUID 去重；保存失败会回滚整批导入。
- 月度和年度周期规则保留原始日期锚点，例如 1 月 31 日会临时夹到 2 月 28 日，并在 3 月恢复到 31 日。
- 财务领域测试从 3 条扩展到 8 条，新增 CSV 一致性、未来备份拒绝、替换恢复快照、旧备份兼容和月底锚点覆盖。

## 验证

- `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/flashcount-fix-final-build CODE_SIGNING_ALLOWED=NO build`
- 结果：无签名 iOS 构建成功。
- `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/flashcount-fix-tests CODE_SIGNING_ALLOWED=NO test`
- 结果：8 条测试全部通过，0 失败。
- `git diff --check`
- 结果：通过。

## 剩余限制

- SwiftData 与提醒 JSON 文件属于两个独立存储，无法提供跨存储的严格原子事务；数据库会先提交，提醒文件写入失败仍会向调用方报告。
- 已经在旧版本中发生日期漂移且没有锚点的周期规则，只能以当前 `nextDueDate` 的日期作为迁移锚点，无法反推出最初设置的日期。
- 提醒通知重新调度仍是尽力执行，系统通知权限或调度失败不会回滚已成功恢复的数据。
- 尚未对超大 CSV/备份文件建立性能基准或文件系统故障注入测试。
