# 发薪周期报表

## 目的

在日报、周报、月报和年报之外增加按全局发薪日划分的周期报，使发薪周期拥有独立的当前报告、历史报告、上期对比、趋势聚合和本地提醒能力。

## 影响文件

- `FlashCount/Services/FinanceServices/ReportPeriodCalculator.swift`
- `FlashCount/Services/FinanceServices/ReportService.swift`
- `FlashCount/Services/SystemServices/ReportReminderNotificationService.swift`
- `FlashCount/Services/SystemServices/NotificationScheduleCoordinator.swift`
- `FlashCount/Views/Report/ReportView.swift`
- `FlashCount/Views/Report/ReportReminderSettingsView.swift`
- `FlashCount/Views/Onboarding/OnboardingView.swift`
- `FlashCountTests/ReportDomainTests.swift`
- `FlashCountTests/AppRoutingTests.swift`
- `FlashCountUITests/FlashCountSmokeTests.swift`
- `docs/change-logs/2026-07-15-01-pay-cycle-report.md`

## 行为变化

- 报表周期新增“周期报”，根据设置中的发薪日计算 `[本次发薪日, 下次发薪日)` 区间。
- 当前周期报统计从本次发薪日到当前时刻，并与上一个发薪周期的相同已流逝时长比较。
- 历史和通知周期报展示刚结束的完整发薪周期，支持前后周期导航；月末发薪日会自动适配 28、29、30、31 日。
- 周期报按日生成趋势桶，并复用收支概览、分类构成、消费排行、洞察、连续记账和发薪周期预算展示。
- 报表提醒新增周期报选项，在全局发薪日按所选送达时间触发；点击通知打开对应的完整周期报告。
- 报表周期按钮改用独立的无障碍标识，避免周报与周期报同为按日粒度时发生标识冲突。

## 验证

- 报表领域测试 18 项通过，覆盖发薪日 25 日、31 日跨二月、周期聚合、环比、日粒度时间桶和周期提醒日期。
- 全部 75 项单元测试通过，零失败。
- 新增的周期报切换 UI 测试通过，确认报表入口可见、可选择并展示周期范围。
- Release iOS 模拟器构建通过。
- `xcodegen generate` 与 `git diff --check` 通过。

## 剩余限制

- 周期报与其他报表一样基于本地交易实时计算，不持久化历史快照。
- 月末周期报提醒使用滚动本地通知计划；长期不打开 App 时无法无限补排未来通知。
