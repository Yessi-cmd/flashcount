import Foundation

/// 漏掉的周期账怎么补：让用户逐笔确认，还是启动时自动生成。
/// 默认「先确认」——自动生成会在用户不知情时改动账本。
enum RecurringCatchUpMode: String, CaseIterable, Identifiable {
    case review
    case automatic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .review: return "先确认再补账"
        case .automatic: return "自动补账"
        }
    }

    var explanation: String {
        switch self {
        case .review: return "打开周期账单页后，逐笔确认遗漏的周期记录"
        case .automatic: return "App 启动时自动生成已经到期的周期记录"
        }
    }
}

/// 补账模式的读写，存在 `UserDefaults`。未知值一律回落到默认的「先确认」。
enum RecurringCatchUpPreferences {
    static let storageKey = "recurringCatchUpMode"
    static let defaultMode: RecurringCatchUpMode = .review

    static var mode: RecurringCatchUpMode {
        mode(for: UserDefaults.standard.string(forKey: storageKey))
    }

    static func mode(for rawValue: String?) -> RecurringCatchUpMode {
        guard let rawValue, let mode = RecurringCatchUpMode(rawValue: rawValue) else {
            return defaultMode
        }
        return mode
    }
}
