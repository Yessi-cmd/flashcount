# 报表周期领域模型

## 目的

将报表周期、统计区间和提醒偏好从界面与即时日期计算中拆出，建立可测试的报表领域边界，并为日报、周报、月报和年报提供一致的当前周期与定时报表语义。

## 影响文件

- `FlashCount/Services/FinanceServices/ReportPeriodCalculator.swift`
- `FlashCount/Services/FinanceServices/ReportService.swift`
- `FlashCount/Services/DataServices/ReportReminderPreferencesStore.swift`
- `FlashCountTests/ReportDomainTests.swift`
- 生成的 `FlashCount.xcodeproj/project.pbxproj`
- `docs/change-logs/2026-07-13-02-report-period-domain.md`

## 行为变化

- 报表周期扩展为日报、周报、月报和年报，并为每种周期定义小时、日、周或月粒度的类型化时间桶。
- 所有统计区间统一采用左闭右开 `[start, end)` 语义；应用内报表统计当前已流逝区间，定时周报、月报和年报统计最近完成的完整周期。
- 当前周期与上一周期按相同已流逝长度比较，完整周期与紧邻的上一完整周期比较；周首固定为周一。
- `ReportService` 接受显式报表目标，同时保留现有应用内调用的兼容入口，并基于目标日期计算连续记账天数。
- 新增本地 `UserDefaults` 报表提醒偏好存储，支持周期集合、投递时间及周/月/年投递日期，并在读取时规范化越界值。

## 验证

- 运行全部 40 个单元测试并通过；其中报表领域测试覆盖日报对齐区间、完整周/月/年周期、当前周期同比、时间桶粒度、服务聚合边界以及提醒偏好持久化与损坏数据回退。
- Debug 和 Release iOS 模拟器构建均通过。
- `git diff --check` 通过。

## 剩余限制

- 当前仅提供提醒偏好的本地持久化模型，尚未实现系统通知授权与调度。
- 现有报表界面继续通过兼容属性读取时间桶；针对日报和年报的专用展示与提醒设置界面仍需后续接入。
