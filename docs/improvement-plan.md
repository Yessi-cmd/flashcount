# FlashCount 项目分批改进计划

> **注（2026-07-26）**：本文的优先级排序已由 [`docs/remediation-plan.md`](remediation-plan.md) 取代，保留作架构拆分方案参考。
>
> 基于对 ~21,000 行 Swift 代码的全面审查，本文档按优先级和依赖关系，将改进工作拆分为 7 个可独立交付的阶段。

---

## 当前状态总览

| 维度 | 现状 | 问题等级 |
|------|------|---------|
| 文件规模 | DataBackupService 1125行、LedgerView 1109行、ReportView 1114行、Category 504行 | 🔴 严重 |
| 架构分层 | 无 MVVM，视图直接承载筛选/排序/分组/统计逻辑 | 🔴 严重 |
| 代码重复 | 8处 `if #available(iOS 26.0, *)` + 10处 `@available` 分布在5个文件 | 🟡 中等 |
| 错误处理 | 20+ 处 `try?` 静默丢弃错误，`print()` 替代结构化日志 | 🟡 中等 |
| 测试 | 仅 8 个测试文件，无视图/性能/可访问性测试，全部塞在 810 行单文件 | 🟡 中等 |
| 性能 | Color(hex:) 重复创建 Scanner，makePresentation() 每次筛选全量遍历 | 🟢 较轻 |
| Widget | 仅 deep link 跳转，不展示数据，颜色硬编码 | 🟢 较轻 |
| CI/工具 | 无 SwiftLint/SwiftFormat/CI | 🟢 较轻 |

---

## 阶段总览

```
Phase 1 (基础) ─── 独立，可直接开始
    │
Phase 2 (去重) ─── 独立，可直接开始
    │
Phase 3 (拆分) ─── 建议 Phase 2 之后（避免合并冲突）
    │
Phase 4 (分层) ─── 依赖 Phase 3（文件已拆分后提取逻辑更安全）
    │
Phase 5 (测试) ─── 依赖 Phase 4（ViewModel 可用后再写测试）
    │
Phase 6 (Widget) ─ 独立，随时可做
    │
Phase 7 (性能) ─── 独立，随时可做
```

| 阶段 | 内容 | 时间 | 风险 | 可独立交付 |
|------|------|------|------|-----------|
| P1 | 日志 + try?修复 + Color缓存 | 1天 | 极低 | ✅ |
| P2 | Liquid Glass 代码去重 | 1天 | 低 | ✅ |
| P3 | 巨型文件拆分 | 2-3天 | 中 | ✅ |
| P4 | 引入 ViewModel 层 | 3-4天 | 中 | ✅ |
| P5 | 测试补充 + Lint | 2-3天 | 低 | ✅ |
| P6 | Widget 完善 | 1天 | 低 | ✅ |
| P7 | 性能优化 | 1天 | 低 | ✅ |
| **总计** | | **11-14天** | | |

---

## Phase 1：基础 — 日志、错误处理、Color 缓存

**目标**：建立结构化日志系统，修复矛盾的错误处理，消除 Color(hex:) 的性能开销。不动 UI，无回归风险。

### 1.1 引入 os.Logger 替代 print()

新建 `FlashCount/Core/Logging.swift`：

```swift
import OSLog

enum AppLog {
    static let dataStore  = Logger(subsystem: "com.flashcount.app", category: "dataStore")
    static let backup     = Logger(subsystem: "com.flashcount.app", category: "backup")
    static let recurring  = Logger(subsystem: "com.flashcount.app", category: "recurring")
    static let notification = Logger(subsystem: "com.flashcount.app", category: "notification")
    static let general    = Logger(subsystem: "com.flashcount.app", category: "general")
}
```

**替换清单**（9 处 `print()` → `AppLog.xxx.error(...)`）：

| 文件 | 行 | 替换 |
|------|-----|------|
| `FlashCountApp.swift` | 158 | `print("提醒通知重建前读取失败:")` → `AppLog.notification.error(...)` |
| `ErrorHandling.swift` | 116 | `print("数据自检修复最终保存失败:")` → `AppLog.dataStore.error(...)` |
| `RecurringService.swift` | 32 | `print("读取周期规则失败:")` → `AppLog.recurring.error(...)` |
| `DefaultDataService.swift` | 多处 | 对应替换 |
| `ReminderStore.swift` | 多处 | 对应替换 |

> 注意：`#if DEBUG` 块中的 `print()` 保留不动。

### 1.2 修复矛盾的 try?

**必须修**：
- `FlashCountApp.swift:199`：`try? modelContext.save()` → `if let error = safeSave(modelContext) { AppLog.dataStore.error("UITest data save failed: \(error)") }`

**添加日志**（fire-and-forget 场景中 `try?` 合理，但需记录失败）：
- `FlashCountApp.swift:156`：通知重建 Task 中添加 `AppLog.notification.error(...)`
- `DataBackupService.swift:1122-1123`：同上
- `ReportReminderNotificationService.swift:273/279/284`：同上
- `DataBackupService.swift:910`：日志记录 journal 清理失败

**接受现状**（合理的 `try?`）：
- `DataBackupService.swift:16`：回退解码路径
- `ReportReminderPreferencesStore.swift:71`：数据可选，不存在即跳过
- `ReminderStore.swift:20/28`：旧版迁移兼容
- `NotificationScheduleCoordinator.swift:194/201`：缓存文件读取

### 1.3 Color(hex:) 添加缓存

文件：`FlashCount/Core/Extensions.swift:60-84`

`Color(hex:)` 使用 `Scanner` 逐次解析 —— DesignSystem 启动时调用 ~40 次，应用全局 ~110 次。添加 NSCache：

```swift
private let hexColorCache: NSCache<NSString, UIColor> = {
    let cache = NSCache<NSString, UIColor>()
    cache.countLimit = 128
    return cache
}()

extension Color {
    init(hex: String) {
        let key = hex as NSString
        if let cached = hexColorCache.object(forKey: key) {
            self.init(cached)
            return
        }
        // ... 原有解析逻辑 ...
        let uiColor = UIColor(red: r, green: g, blue: b, alpha: a)
        hexColorCache.setObject(uiColor, forKey: key)
        self.init(uiColor)
    }
}
```

### Phase 1 验证

```bash
xcodegen generate && xcodebuild -project FlashCount.xcodeproj \
  -scheme FlashCount -configuration Debug | grep -E "error:|warning:"
# 预期：0 error, 0 warning（新 Logger 引入的 warning 除外）
```

---

## Phase 2：Liquid Glass 代码去重

**目标**：将 8 处 `if #available(iOS 26.0, *)` 分支 + 10 处 `@available(iOS 26.0, *)` 私有属性抽象为 3 个可复用组件。

### 现状分析

| 文件 | 行数 | 重复组件 | iOS 26 变体 | 旧系统变体 |
|------|------|---------|------------|-----------|
| `MainTabView.swift` | 188 | Tab Bar | `modernTabBar` (50行) | `legacyTabBar` (45行) |
| `LedgerView.swift` | 588 | 日期筛选条 | `liquidGlassDateFilterStrip` (33行) | `legacyDateFilterStrip` (24行) |
| `ReportView.swift` | 218 | 周期选择器 | `liquidGlassPeriodPicker` (28行) | `legacyPeriodPicker` (19行) |
| `ReportView.swift` | 279 | 范围导航器 | `liquidGlassRangeNavigator` (57行) | `legacyRangeNavigator` (32行) |
| `QuickEntryView.swift` | 243 | 收支切换 | `liquidGlassTypeToggle` (10行) | 内联旧版 |
| `QuickEntryView.swift` | 502 | 底部控制栏 | 内联 iOS 26 | 内联旧版 |
| `QuickEntryControls.swift` | 34 | 键盘按键 | `.glass` style | 旧背景 |
| `QuickEntryControls.swift` | 102 | 提交按钮 | `.glassProminent` | 旧按钮 |

**重复代码估算：~280 行**

### 实施方案

新建 `FlashCount/Views/Components/PlatformAdaptiveViews.swift`（~200 行），封装 3 个组件：

**组件 ①：`AdaptiveChipGroup<T>`** — 替代 4 处重复
```swift
/// 自适应分段选择器。iOS 26 → GlassEffectContainer + liquidGlassSurface
/// 旧系统 → HStack + Capsule 背景
struct AdaptiveChipGroup<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    let spacing: CGFloat
}
```
替换：`LedgerView.dateFilterStrip`、`ReportView.periodPicker`、`QuickEntryView.typeToggle`

**组件 ②：`AdaptiveRangeNavigator`** — 替代 1 处重复
```swift
/// 自适应范围导航器。iOS 26 → GlassEffectContainer + liquidGlassSurface(.circle)
/// 旧系统 → HStack + 普通按钮
struct AdaptiveRangeNavigator: View {
    let title: String; let subtitle: String; let canGoNext: Bool
    let onPrevious: () -> Void; let onNext: () -> Void
}
```
替换：`ReportView.rangeNavigator`

**组件 ③：`AdaptiveTabBar`** — 替代 1 处重复
```swift
/// 自适应底部标签栏
struct AdaptiveTabBar: View {
    @Binding var selectedTab: Int
    let tabs: [TabItem]
    let onPrimaryAction: () -> Void
}
```
替换：`MainTabView.customTabBar`

> **QuickEntryControls 的键盘按键和提交按钮**交互模式特殊（单个按钮级别的风格切换），保留轻量内联分支，不强行抽象。

### Phase 2 验证

- iOS 17 模拟器：所有 UI 与重构前视觉一致
- iOS 26 模拟器：Liquid Glass 效果正常
- `/visualDirectionExploration` 启动参数下效果不变

---

## Phase 3：巨型文件拆分

**目标**：将 4 个超过 500 行的文件拆分为职责清晰的独立文件。纯代码搬迁，零逻辑改动。

### 3.1 DataBackupService（1125 行 → 4 个文件）

| 新文件 | 内容 | 行数 |
|--------|------|------|
| `Services/DataServices/BackupDTOs.swift` | 14 个 DTO + `CodableMoney` + `SemanticVersion` + `ImportError` + `ImportMode` + `ImportResult` + `BackupPreview` | ~250 |
| `Services/DataServices/BackupExportService.swift` | `exportJSON()`, `exportToFile()`, `previewJSON()` | ~150 |
| `Services/DataServices/BackupImportService.swift` | `importJSON()`, `recoverPendingImport()`, journal 机制, `applyExternalSettings()`, 校验方法 | ~300 |
| `Services/DataServices/DataBackupService.swift` | 门面协调器，委托给 Import/Export Service | ~100 |

> `DataBackupService` 仅被 3 个文件引用（`SettingsView`, `DefaultDataService`, 自身），拆分安全。

### 3.2 Category.swift（504 行 → 3 个文件）

| 新文件 | 内容 | 行数 |
|--------|------|------|
| `Models/CategoryData.swift` | `CategoryItemDefinition`, `CategoryGroupDefinition`, `expenseCategoryGroups()`, `incomeCategoryGroups()` 等默认数据定义 | ~180 |
| `Models/Category+Logic.swift` | `rootName()`, `rootCategories`, `childCategories`, `rootCategoryName`, `reportDisplayName`, `reportIcon`, `reportColorHex`, `isSalaryIncome`, 旧版兼容映射 | ~160 |
| `Models/Category.swift` | `@Model` 定义 + `init` | ~60 |

### 3.3 LedgerView.swift（1109 行 → 4 个文件）

| 新文件 | 内容 | 行数 |
|--------|------|------|
| `Views/Ledger/LedgerPresentationBuilder.swift` | `LedgerPresentation` 结构体 + `makePresentation()` | ~120 |
| `Views/Ledger/LedgerSummaryCard.swift` | `monthlySummaryCard` + `summarySecondaryMetric` + `summaryPeriodDescription` | ~100 |
| `Views/Ledger/LedgerBudgetCard.swift` | `ledgerBudgetCard` + `budgetAccent` | ~40 |
| `Views/Ledger/LedgerTransactionList.swift` | `transactionList` + 删除/撤销/批量操作 | ~200 |
| `Views/Ledger/LedgerView.swift` | body + toolbar + sheet + 导航结构 | ~400 |

### 3.4 ReportView.swift（1114 行 → 3 个文件）

| 新文件 | 内容 | 行数 |
|--------|------|------|
| `Views/Report/ReportObservedContent.swift` | `ReportObservedContent` + `GenerationKey` + `MidnightTaskID` | ~400 |
| `Views/Report/ReportChartCards.swift` | `timeBucketBarChart` + `categoryPieChart` + `topCategoriesCard` + `insightsCard` + `smartAnalysisCard` | ~280 |
| `Views/Report/ReportSummaryCard.swift` | `summaryCard` + `streakCard` + `budgetCard` | ~180 |
| `Views/Report/ReportView.swift` | 周期选择 + 范围导航 + 导航状态 + 子组件组合 | ~300 |

### 3.5 FinanceDomainTests.swift（810 行 → 8 个文件）

| 新文件 | 内容 |
|--------|------|
| `Tests/BackupServiceTests.swift` | 备份导入/导出/恢复/版本校验 |
| `Tests/RecurringDomainTests.swift` | 周期规则生成、幂等性、锚定日 |
| `Tests/ReminderDomainTests.swift` | 提醒 CRUD、迁移、持久化 |
| `Tests/BudgetDomainTests.swift` | 预算分析、预警等级、分类预算 |
| `Tests/CategoryDomainTests.swift` | 分类层级、默认数据 |
| `Tests/PrivacyLockTests.swift` | 隐私锁状态转换 |
| `Tests/CashPoolDomainTests.swift` | 资金池增删改 |
| `Tests/CSVImportTests.swift` | CSV 导入去重 |

### Phase 3 验证

```bash
xcodegen generate
xcodebuild -project FlashCount.xcodeproj -scheme FlashCount test
# 所有现有测试必须通过
xcodebuild archive -project FlashCount.xcodeproj -scheme FlashCount \
  -configuration Release -archivePath build/FlashCount.xcarchive
# 打包流程正常
```

---

## Phase 4：引入 ViewModel 层

**目标**：将视图中的业务逻辑提取到 `@MainActor ObservableObject`。当前项目唯一的 ObservableObject 是 `PrivacyLockService`。

### 关键约束

- `@Query` 只能在 View 内使用 → ViewModel 改用 `FetchDescriptor` + `modelContext.fetch()`
- `@AppStorage` 通过 `UserDefaults` 读取或作为初始化参数
- 所有 ViewModel 标记 `@MainActor`（与现有服务层一致）

### 4a. LedgerViewModel（可提取 ~210 行）

新建 `FlashCount/Views/Ledger/LedgerViewModel.swift`：

```swift
@MainActor
final class LedgerViewModel: ObservableObject {
    // MARK: - @Published 筛选状态（15 个属性）
    @Published var searchText = ""
    @Published var debouncedSearchText = ""
    @Published var dateFilter: LedgerPeriodFilter = .payCycle
    @Published var typeFilter: TransactionTypeFilter = .all
    @Published var categoryFilterId: UUID?
    @Published var minAmountText = ""
    @Published var maxAmountText = ""
    @Published var sortField: TransactionSortField = .date
    @Published var sortDirection: TransactionSortDirection = .descending
    @Published var visibleTransactionLimit = 200
    @Published var historicalTransactions: [Transaction] = []
    @Published var isSelecting = false
    @Published var selectedIds = Set<UUID>()
    @Published var undoInfo: DeletedTransactionSnapshot?
    // ... 其他状态

    // MARK: - 纯函数
    func buildPresentation(transactions: [Transaction], categories: [Category],
                           privacyLock: PrivacyLockService, limit: Int) -> LedgerPresentation

    // MARK: - 副作用
    func loadHistoricalTransactions(modelContext: ModelContext)
    func deleteTransaction(_ t: Transaction, modelContext: ModelContext)
    func undoDelete(modelContext: ModelContext)
    func batchDeleteSelected(from: [Transaction], modelContext: ModelContext)

    // MARK: - 计算属性
    var hasActiveFilters: Bool
    var activeFilterCount: Int
    var presentationTransactions: [Transaction]
}
```

LedgerView 精简到 ~400 行，仅保留 `@Query`、`@Environment`、body 和子视图组合。

### 4b. ReportViewModel（可提取 ~100 行）

新建 `FlashCount/Views/Report/ReportViewModel.swift`：

```swift
@MainActor
final class ReportViewModel: ObservableObject {
    @Published var state: ReportLoadState = .loading
    @Published var retryToken = 0
    @Published var selectedBucketID: Date?
    @Published var showChartDetails = false

    func generateReport(modelContext: ModelContext, period: ReportPeriod,
                        target: ReportTarget, payday: Int,
                        transactions: [Transaction], budgets: [Budget])
    var transactionDigest: Int  // 触发 .task(id:) 的哈希
}
```

`ReportObservedContent` 保持 ~680 行（图表渲染代码无需变动），但逻辑层可单独测试。

### 4c. MainTabCoordinator（可提取 ~110 行）

新建 `FlashCount/Views/MainTabCoordinator.swift`：

```swift
@MainActor
final class MainTabCoordinator: ObservableObject {
    @Published var presentedSheet: MainSheetDestination?
    @Published var pendingForegroundReport: ReportRoute.Request?
    @Published var showPlusActions = false

    func handleDeepLink(_ url: URL)
    func processQuickEntryRequestIfNeeded()
    func processReportRequestIfNeeded()
    func presentPendingForegroundReportIfPossible()
}
```

> **注意**：空闲计时器逻辑（`.task(id:)` + `DragGesture`）与 SwiftUI 视图生命周期紧密耦合，Phase 4 中**保留在 View 层**，后续迭代再处理。

### Phase 4 验证

- 所有 Tab 切换、筛选、排序、删除、撤销功能与重构前一致
- 报表切换周期、前后台切换正常
- `FlashCountSmokeTests` 通过

---

## Phase 5：测试补充 + 代码质量工具

### 5.1 SwiftLint + SwiftFormat

新建 `.swiftlint.yml`：
```yaml
opt_in_rules:
  - force_unwrapping
  - orphaned_doc_comment
  - redundant_optional_initialization
  - unneeded_break_in_switch
line_length: 140
file_length:
  warning: 500
  error: 800
function_body_length:
  warning: 100
```

新建 `.swiftformat`（匹配现有风格：4 空格缩进，120 字符行长）。

### 5.2 ViewModel 单元测试

| 新测试文件 | 覆盖内容 |
|-----------|---------|
| `LedgerViewModelTests.swift` | empty/category filter/type filter/sort/amount filter/search text edge cases |
| `ReportViewModelTests.swift` | empty data / single transaction / privacy-locked income / period boundary |
| `LedgerFilterStateTests.swift` | filter equality / active count / custom sort detection |

使用 `FinanceDomainTests.makeContext()` 的 in-memory `ModelContainer` 模式。

### 5.3 性能测试

| 测试 | 场景 |
|------|------|
| `testMakePresentationPerformance` | 5,000 笔交易下的 `makePresentation()` |
| `testColorHexInitPerformance` | 1,000 次连续 `Color(hex:)` |
| `testReportGenerationPerformance` | 10,000 笔交易下的报表生成 |

### Phase 5 验证

```bash
xcodebuild test -project FlashCount.xcodeproj -scheme FlashCount \
  -destination 'platform=iOS Simulator,name=iPhone 16'
# 全部通过
```

---

## Phase 6：Widget 完善

### 6.1 App Group 数据共享

`project.yml` 添加 App Group capability → `group.com.flashcount.app`。

主 App 中每次 `safeSave()` 成功后，将摘要写入共享 UserDefaults：
```swift
let sharedDefaults = UserDefaults(suiteName: "group.com.flashcount.app")
let summary = WidgetSummary(todayExpense: ..., monthExpense: ..., streakDays: ...)
sharedDefaults?.set(try? JSONEncoder().encode(summary), forKey: "widgetSummary")
```

### 6.2 Widget 展示实际数据

更新 `QuickEntryWidgetView`：
- `.systemSmall`：今日支出金额 + 笔数
- `.accessoryRectangular`：本月支出 + 连续记账天数
- `.accessoryCircular`：保持不变（空间有限）

### 6.3 Widget 颜色统一

替换硬编码 `Color(red: 0.306, green: 0.463, blue: 0.416)` → 在 Widget extension 中定义匹配 `DesignSystem.primaryColor` 的本地常量。

### 6.4 Timeline 刷新策略

```swift
// 从 .never → 活跃时段每 15 分钟刷新
func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    let entry = QuickEntryTimelineEntry(date: Date(), summary: loadSummary())
    let calendar = Calendar.current
    let hour = calendar.component(.hour, from: Date())
    let policy: TimelineReloadPolicy = (6...23).contains(hour)
        ? .after(Calendar.current.date(byAdding: .minute, value: 15, to: Date())!)
        : .never
    completion(Timeline(entries: [entry], policy: policy))
}
```

### Phase 6 验证

- Widget 桌面显示今日支出金额
- 记账后 Widget 在 15 分钟内更新
- 点击 Widget 正确 deep link 到记账页

---

## Phase 7：性能优化

### 7.1 交易列表缓存

`makePresentation()` 在筛选未变时直接返回缓存结果：
```swift
@State private var cachedPresentation: LedgerPresentation?
@State private var lastFilterHash: Int?

func makePresentation(limit: Int) -> LedgerPresentation {
    let currentHash = filterHash  // 组合所有筛选条件
    if let cached, lastFilterHash == currentHash, limit <= cached.visibleTransactionCount {
        return cached
    }
    let new = buildPresentation(limit: limit)
    cachedPresentation = new
    lastFilterHash = currentHash
    return new
}
```

### 7.2 transactionDigest 精简

`ReportObservedContent.transactionDigest`（第 468-491 行）对每笔交易的每个属性做 hash。精简为只 hash `transaction.id` + `transaction.amount`：
```swift
private var transactionDigest: Int {
    var hasher = Hasher()
    for t in observedTransactions {
        hasher.combine(t.id)
        hasher.combine(t.amount)
    }
    for b in budgets {
        hasher.combine(b.id)
        hasher.combine(b.monthlyLimit)
    }
    return hasher.finalize()
}
```

### 7.3 NumberFormatter 确认无重复创建

- `DisplayFormatter` 已使用 `static let` ✅
- 确认 `compactCurrency()` (ReportView.swift) 中 `String(format:)` 的使用合理

### Phase 7 验证

```bash
# Instruments Time Profiler 对比优化前后
# makePresentation() 目标：1000 笔交易 < 50ms
xcodebuild test -project FlashCount.xcodeproj -scheme FlashCount \
  -only-testing:FlashCountTests/PerformanceTests
```

---

## 风险与应对

| 风险 | 等级 | 应对 |
|------|------|------|
| 文件拆分导致 import 缺失 | 低 | 每个新文件复制父文件的 import 声明，不引入新模块边界 |
| MVVM 提取改变 View 行为 | 中 | Phase 3 先纯拆分，Phase 4 保持签名不变，每步测试 |
| @Observable 兼容性 | 低 | iOS 17 完全支持。如遇问题改用 `ObservableObject + @Published`（`PrivacyLockService` 已验证） |
| AltStore 打包流程中断 | 低 | 不改 `project.yml` 的 target/build settings/signing。新文件在已有目录中自动被 `path: FlashCount` 包含 |

---

## 不改的内容

以下保持现状，避免过度工程化：

- **不引入第三方依赖框架**（保持纯 Apple 技术栈）
- **不拆分 Model 文件中的 `@Model` 定义**（SwiftData 要求）
- **不变更 AltStore 打包流程**
- **不引入网络层/云同步**（App 定位 Local-first）
- **QuickEntryControls 的键盘按钮**保留轻量内联分支（交互特殊，抽象收益低）
- **MainTabView 的空闲计时器** Phase 4 保留在 View 中（与 `.task(id:)` 耦合）
