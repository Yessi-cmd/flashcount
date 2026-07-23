# 单账本承诺与 P0/P1 缺陷修复

## 目的

- 将产品定位明确为个人单账本，消除公开文案与实际数据策略的冲突。
- 修复备份恢复、资金池投影、启动初始化、提醒迁移与通知替换中的高优先级静默失败或数据失真风险。
- 改善关键记账流程的可达性、输入校验和导航稳定性。

## 受影响文件

- 产品与发布配置：`README.md`、`project.yml`、`FlashCount/FlashCount.entitlements`、`FlashCount/PrivacyInfo.xcprivacy`。
- 数据与启动：`DataBackupService.swift`、`CSVTransactionService.swift`、`ReminderStore.swift`、`DefaultDataService.swift`、`RecurringService.swift`、`ErrorHandling.swift`、`FlashCountSchema.swift`、`FlashCountApp.swift`。
- 通知与界面：`NotificationScheduleCoordinator.swift`、设置页、主标签栏、引导页、快捷记账及相关账本/资产/预算/周期规则视图。
- 回归测试：`FinanceDomainTests.swift`、`NotificationScheduleCoordinatorTests.swift`、`FlashCountSmokeTests.swift`。

## 行为变化

- 备份导入统一以 `UUID` 去重；恢复缺失的交易资金池变动、时间戳、分类合并关系、分类预算映射及周期交易来源关系。
- CSV 支持带逗号、转义引号和换行的字段，校验表头，并向用户报告每一条跳过记录的原因。
- 数据自检仅修复可确定的缺失账本；不再为交易猜测分类或把无效金额改成 `1`。
- 启动过程改为显式成功/失败状态；默认数据、导入恢复、提醒迁移和首个有界周期交易批次完成后才显示主界面，剩余周期交易会让出主线程后继续处理。
- 损坏的旧提醒文件会被保留并阻止迁移完成标记；通知重建失败会恢复旧的受管通知；未获时间敏感通知许可时会降级为普通通知。
- 默认锁屏通知不展示用户输入的提醒标题与备注，可在设置中显式开启；发薪日或该隐私设置变更会重新排程。
- 采用显式 SwiftData 版本化 schema；容器创建失败时不删除数据并显示失败说明。
- 主导航栏常驻；引导支持滚动和固定完成按钮；快捷记账成功后由用户主动选择继续或完成；关键可点击行具备按钮语义，金额保存按钮与实际金额校验一致。

## 验证

- 已执行 `xcodegen generate`。
- 已通过 iPhone 17 Pro（iOS 26.2）模拟器构建、启动并检查主界面导航。
- 已运行完整模拟器测试：101 passed，0 failed，0 skipped。
- 已检查构建产物包含 `PrivacyInfo.xcprivacy`，其中声明无跟踪、无收集数据和 UserDefaults 的 `CA92.1` 理由。

## 剩余限制

- 系统通知的最终投递仍受用户授权、系统专注模式及 iOS 待处理通知容量限制；应用会显示排程错误或容量状态，但无法绕过系统策略。
- 账本和报表的大数据分页/聚合优化不属于本批数据正确性修复范围，后续可单独进行性能改造。
