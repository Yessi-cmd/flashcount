import AppIntents

/// 快速记账 App Intent
/// 用于 Siri / iOS Shortcuts / Back Tap / 锁屏 Widget
struct QuickAddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "快速记账"
    static var description = IntentDescription("打开 FlashCount 快速记账页面")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // 打开 App 后由 MainTabView 处理显示快速记账页面
        return .result()
    }
}

/// App Shortcuts Provider - 注册到 Shortcuts App
struct FlashCountShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickAddExpenseIntent(),
            phrases: [
                "记一笔 \(.applicationName)",
                "用 \(.applicationName) 记账",
                "打开 \(.applicationName) 记账"
            ],
            shortTitle: "快速记账",
            systemImageName: "plus.circle.fill"
        )
    }
}
