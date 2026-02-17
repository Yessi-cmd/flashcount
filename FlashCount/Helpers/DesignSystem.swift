import SwiftUI

/// App 设计系统常量
enum DesignSystem {

    // MARK: - 品牌色

    /// 主渐变色
    static let primaryGradient = LinearGradient(
        colors: [Color(hex: "#667EEA"), Color(hex: "#764BA2")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 收入渐变
    static let incomeGradient = LinearGradient(
        colors: [Color(hex: "#11998E"), Color(hex: "#38EF7D")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 支出渐变
    static let expenseGradient = LinearGradient(
        colors: [Color(hex: "#FC5C7D"), Color(hex: "#6A82FB")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 危险渐变
    static let dangerGradient = LinearGradient(
        colors: [Color(hex: "#FF416C"), Color(hex: "#FF4B2B")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 警告渐变
    static let warningGradient = LinearGradient(
        colors: [Color(hex: "#F7971E"), Color(hex: "#FFD200")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - 单色

    static let primaryColor = Color(hex: "#667EEA")
    static let incomeColor = Color(hex: "#2ED573")
    static let expenseColor = Color(hex: "#FF6B6B")
    static let warningColor = Color(hex: "#FFA502")
    static let dangerColor = Color(hex: "#FF4757")
    static let cardBackground = Color(hex: "#1E1E2E")
    static let surfaceBackground = Color(hex: "#13131A")

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
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCard())
    }
}
