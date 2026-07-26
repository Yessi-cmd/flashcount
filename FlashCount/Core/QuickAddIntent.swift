import AppIntents

/// Siri / 快捷指令 / Back Tap 请求打开记账页的信箱。
///
/// Intent 与 UI 不在同一次进程活动里，所以请求先落在 `UserDefaults`，
/// 由 `MainTabView` 取用。`consume()` 取走即清零——重复消费会让记账页
/// 在用户关掉后又自己弹回来。
enum QuickEntryRoute {
    static let requestKey = "shouldShowQuickEntry"

    static func request(userDefaults: UserDefaults = .standard) {
        userDefaults.set(true, forKey: requestKey)
    }

    @discardableResult
    static func consume(userDefaults: UserDefaults = .standard) -> Bool {
        guard userDefaults.bool(forKey: requestKey) else { return false }
        userDefaults.set(false, forKey: requestKey)
        return true
    }
}

/// 快速记账 App Intent
/// 用于 Siri / iOS Shortcuts / Back Tap / 锁屏 Widget
struct QuickAddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "快速记账"
    static var description = IntentDescription("打开 FlashCount 快速记账页面")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        QuickEntryRoute.request()
        return .result()
    }
}

/// App Shortcuts Provider - 注册到 Shortcuts App
struct FlashCountShortcuts: AppShortcutsProvider {
    static func refreshSystemRegistration() {
        updateAppShortcutParameters()
    }

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
