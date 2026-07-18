# 将提醒迁移到 SwiftData

## 目的

将提醒事项从独立 Documents JSON 文件迁入现有的本地 SwiftData 存储，消除提醒与账本数据分属两套主存储的边界，同时确保覆盖安装后的既有提醒和账本数据不会被删除。

## 受影响文件

- `FlashCount/Models/Reminder.swift`
- `FlashCount/Models/ReminderItem.swift`
- `FlashCount/FlashCountApp.swift`
- `FlashCount/Services/DataServices/ReminderStore.swift`
- `FlashCount/Services/DataServices/DefaultDataService.swift`
- `FlashCount/Services/DataServices/DataBackupService.swift`
- `FlashCount/Services/SystemServices/NotificationScheduleCoordinator.swift`
- `FlashCount/Services/SystemServices/ReminderNotificationService.swift`
- `FlashCount/Services/SystemServices/ReportReminderNotificationService.swift`
- `FlashCount/Views/Reminder/ReminderView.swift`
- `FlashCount/Views/Report/ReportReminderSettingsView.swift`
- `FlashCountTests/FinanceDomainTests.swift`
- `FlashCountTests/CategoryManagementServiceTests.swift`
- `FlashCountTests/ReportDomainTests.swift`
- `FlashCountTests/TransactionMutationServiceTests.swift`
- `FlashCount.xcodeproj/project.pbxproj`（由 XcodeGen 生成）

## 行为变化

- 新增 `Reminder` SwiftData `@Model`；提醒的创建、完成、删除和查询均通过同一个 `ModelContext` 保存。
- 已安装旧版本在首次启动时会把 `flashcount-reminders.json` 的内容按 UUID 导入 SwiftData；数据库保存成功后才写入迁移标记，旧 JSON 文件不会被删除或覆盖。
- 手动备份仍以 JSON 表示提醒，保证现有备份格式可导入；导入和替换恢复中的提醒现在与其他业务模型同一次 SwiftData save 提交。
- 替换恢复会标记旧 JSON 为已迁移，避免保留的旧文件在恢复后重新注入已经被替换的数据。
- 通知重建改为接收数据库读取的提醒快照，避免 JSON 与数据库双写、双读。
- 对旧版本遗留的“数据库已提交、提醒 JSON 尚未写入”的导入日志，恢复时会把备份中的提醒补入 SwiftData。

## 验证

- `xcodegen generate`
- `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -destination 'platform=iOS Simulator,id=02222C1D-48B3-490A-A9A8-FDC193410982' -derivedDataPath /tmp/flashcount-reminder-swiftdata-tests -only-testing:FlashCountTests/FinanceDomainTests test CODE_SIGNING_ALLOWED=NO`
- 完整 `FlashCountTests` 单元测试：83/83 通过。
- `testMainTabBarHidesAfterIdleAndReturnsOnInteraction` UI 测试单独复跑通过；此前一次全量测试中的该项失败为既有时序波动。
- 已运行 `./scripts/package-altstore.sh`；当前机器的 CoreSimulator 服务不可用，导致 `actool` 在资源编译阶段无法找到 simulator runtime，未生成或替换 IPA。
- 新增覆盖：旧 JSON 一次性迁移且保留原文件、提醒 CRUD、备份替换恢复、保留旧文件时的权威替换恢复、以及旧 SwiftData 存储增加 `Reminder` 模型后的交易保留。

## 剩余限制

- 覆盖安装必须保持相同的 App bundle identifier；删除 App、改用不同 bundle identifier，或手动清除系统 App 数据都会清空系统数据容器。
- 旧 JSON 会作为本地回退副本继续保留，不会自动清理；后续如需提供“清理旧提醒文件”入口，应先让用户确认并保留可恢复备份。
- 本地通知仍受系统权限、Focus 模式和 iOS 待处理通知容量限制。
- 当前环境的 CoreSimulator 服务异常；恢复该服务后需要重新执行 AltStore 打包，才能交付已验证的 IPA。
