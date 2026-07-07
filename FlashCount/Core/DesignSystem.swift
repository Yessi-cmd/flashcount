import SwiftUI

enum AppearancePreference: String, CaseIterable {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// App 设计系统常量
enum DesignSystem {

    // MARK: - 品牌色

    /// 主渐变色
    static let primaryGradient = LinearGradient(
        colors: [Color(hex: "#4EA8F8"), Color(hex: "#67D8B5")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 收入渐变
    static let incomeGradient = LinearGradient(
        colors: [Color(hex: "#18B985"), Color(hex: "#7AE7B9")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 支出渐变
    static let expenseGradient = LinearGradient(
        colors: [Color(hex: "#FF7A70"), Color(hex: "#FFB199")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 危险渐变
    static let dangerGradient = LinearGradient(
        colors: [Color(hex: "#FF5A76"), Color(hex: "#FF8A65")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 警告渐变
    static let warningGradient = LinearGradient(
        colors: [Color(hex: "#F7B731"), Color(hex: "#FFE082")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - 单色

    static let primaryColor = Color(hex: "#4EA8F8")
    static let incomeColor = Color(hex: "#18B985")
    static let expenseColor = Color(hex: "#F26D6D")
    static let warningColor = Color(hex: "#F4A62A")
    static let dangerColor = Color(hex: "#F2556B")

    static let surfaceBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)
        : UIColor(red: 0.965, green: 0.982, blue: 0.992, alpha: 1)
    })

    static let cardBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.12, green: 0.13, blue: 0.18, alpha: 1)
        : UIColor.white
    })

    static let textPrimary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1)
        : UIColor(red: 0.11, green: 0.15, blue: 0.22, alpha: 1)
    })

    static let textSecondary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.68, green: 0.72, blue: 0.80, alpha: 1)
        : UIColor(red: 0.39, green: 0.45, blue: 0.55, alpha: 1)
    })

    static let textTertiary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.45, green: 0.50, blue: 0.58, alpha: 1)
        : UIColor(red: 0.58, green: 0.64, blue: 0.72, alpha: 1)
    })

    static let softFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.07)
        : UIColor(red: 0.93, green: 0.96, blue: 0.98, alpha: 1)
    })

    static let borderColor = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.08)
        : UIColor(red: 0.84, green: 0.90, blue: 0.94, alpha: 1)
    })

    static let dividerColor = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.10)
        : UIColor(red: 0.88, green: 0.92, blue: 0.95, alpha: 1)
    })

    // MARK: - 圆角 & 间距

    static let cornerRadius: CGFloat = 16
    static let smallCornerRadius: CGFloat = 10
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
}

/// 毛玻璃卡片修饰器
struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(DesignSystem.cardPadding)
            .background(DesignSystem.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .stroke(DesignSystem.borderColor, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 8)
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCard())
    }
}
