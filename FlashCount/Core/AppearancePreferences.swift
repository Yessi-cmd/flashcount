import Foundation
import SwiftUI
import UIKit

/// 可选的强调色。存 `UserDefaults`，App 根视图据此设置全局 `.tint`，
/// `DesignSystem.primaryColor` 返回 `Color.accentColor` 跟随该 tint，
/// 因此所有既有页面不需要逐处替换颜色。
enum AccentThemePreference: String, CaseIterable, Identifiable {
    case forest
    case ocean
    case violet
    case rose
    case graphite

    static let storageKey = "accentTheme"
    static let fallback: AccentThemePreference = .forest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forest: return "森林绿"
        case .ocean: return "海洋蓝"
        case .violet: return "紫罗兰"
        case .rose: return "玫瑰"
        case .graphite: return "石墨灰"
        }
    }

    var color: Color {
        Color(uiColor: UIColor { traits in
            let (light, dark) = Self.rgbaValues(self)
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.red, green: value.green, blue: value.blue, alpha: 1)
        })
    }

    static var current: AccentThemePreference {
        guard let rawValue = UserDefaults.standard.string(forKey: storageKey),
              let preference = AccentThemePreference(rawValue: rawValue) else {
            return fallback
        }
        return preference
    }

    private static func rgbaValues(
        _ preference: AccentThemePreference
    ) -> (light: (red: CGFloat, green: CGFloat, blue: CGFloat), dark: (red: CGFloat, green: CGFloat, blue: CGFloat)) {
        switch preference {
        case .forest:
            return ((0.306, 0.463, 0.416), (0.361, 0.561, 0.494))
        case .ocean:
            return ((0.173, 0.408, 0.600), (0.353, 0.565, 0.784))
        case .violet:
            return ((0.404, 0.337, 0.612), (0.545, 0.475, 0.784))
        case .rose:
            return ((0.655, 0.341, 0.420), (0.776, 0.478, 0.553))
        case .graphite:
            return ((0.239, 0.306, 0.349), (0.541, 0.600, 0.643))
        }
    }
}

/// 可选的桌面图标。除「默认」外，每套都预置了与强调色对应的
/// 1024px 图标资源，并在 Info.plist 中注册为 alternate icon。
enum AppIconPreference: String, CaseIterable, Identifiable {
    case original
    case forest
    case ocean
    case violet
    case rose
    case graphite

    static let storageKey = "appIcon"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "默认"
        case .forest: return "森林绿"
        case .ocean: return "海洋蓝"
        case .violet: return "紫罗兰"
        case .rose: return "玫瑰"
        case .graphite: return "石墨灰"
        }
    }

    /// `setAlternateIconName` 需要的名字；nil 表示恢复主图标。
    var alternateIconName: String? {
        switch self {
        case .original: return nil
        case .forest: return "AppIcon-Forest"
        case .ocean: return "AppIcon-Ocean"
        case .violet: return "AppIcon-Violet"
        case .rose: return "AppIcon-Rose"
        case .graphite: return "AppIcon-Graphite"
        }
    }

    /// 设置页预览直接读资源目录里的同名图片。
    var previewImageName: String {
        alternateIconName ?? "AppIcon"
    }

    static var current: AppIconPreference {
        guard let rawValue = UserDefaults.standard.string(forKey: storageKey) else {
            return .original
        }
        return AppIconPreference(rawValue: rawValue) ?? .original
    }
}

/// 切换桌面图标。系统回调成功后才会写 UserDefaults，避免界面显示
/// 已切换但系统实际未生效。
@MainActor
enum AppIconService {
    static func set(_ preference: AppIconPreference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UIApplication.shared.setAlternateIconName(preference.alternateIconName) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        UserDefaults.standard.set(preference.rawValue, forKey: AppIconPreference.storageKey)
    }
}
