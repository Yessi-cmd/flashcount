# 更智能的报表分析

## 目的

让日报、周报、月报、年报和发薪周期报不只展示汇总图表，还能基于本地交易生成可解释、符合各周期特点的指标、预测与行动提示。

## 影响文件

- `FlashCount/Services/FinanceServices/ReportService.swift`
- `FlashCount/Views/Report/ReportView.swift`
- `FlashCountTests/ReportDomainTests.swift`
- `docs/change-logs/2026-07-17-01-smarter-report-analysis.md`

## 行为变化

- 报表新增结构化智能分析，按周期显示笔均、日均或月均支出，以及峰值时段/日期/周/月和活跃区间数量。
- 进行中的周报、月报、年报和发薪周期报在已有足够进度后，按当前平均节奏给出本期支出预测。
- 洞察可识别峰值区间、主要消费分类、分类环比异动、异常大额支出、周末消费集中、支出趋势与结余率。
- 每条洞察都有明确类型和语义颜色；收入与结余率洞察跟随现有隐私锁隐藏。
- 所有计算继续在设备本地完成，不增加网络依赖，金额聚合与预测保持使用 `Decimal`。

## 验证

- 为日报自适应指标、峰值洞察、周末消费集中、结余率隐私标记和当前周期预测增加领域测试。
- `xcodegen generate` 成功，项目已由 `project.yml` 重新生成。
- Debug iOS 模拟器构建通过。
- iPhone 17 Pro（iOS 26.2）模拟器上的 20 项报表领域测试全部通过，0 项失败。
- `scripts/package-altstore.sh` 完成 Release 真机构建及结构、签名、架构、本机路径和隐私数据检查，成功生成规范的 `build/FlashCount-AltStore.ipa`。

## 剩余限制

- 支出预测使用当前周期简单平均节奏，不能预知尚未发生的一次性大额支出。
- 数据量较少时洞察会保持克制，不做复杂推断。
