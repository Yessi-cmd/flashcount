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

    // MARK: - Layout tokens

    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32
    static let cornerRadius: CGFloat = 16
    static let smallCornerRadius: CGFloat = 10
    static let heroCornerRadius: CGFloat = 24
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 20

    // MARK: - Motion tokens

    static let quickAnimation = Animation.easeOut(duration: 0.16)
    static let standardAnimation = Animation.easeInOut(duration: 0.24)
    static let emphasisAnimation = Animation.spring(response: 0.36, dampingFraction: 0.84)
    static let navigationAnimation = Animation.spring(response: 0.44, dampingFraction: 0.86, blendDuration: 0.08)
    static let pageAnimation = Animation.spring(response: 0.52, dampingFraction: 0.90, blendDuration: 0.10)
}

/// 轻量环境光背景。静态渐变提供空间层次，不引入持续动画或离屏模糊。
struct AmbientBackground: View {
    let accent: Color

    var body: some View {
        ZStack {
            DesignSystem.surfaceBackground

            RadialGradient(
                colors: [accent.opacity(0.13), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 330
            )
            .offset(x: -70, y: -120)

            RadialGradient(
                colors: [DesignSystem.primaryColor.opacity(0.07), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 420
            )
            .offset(x: 90, y: 170)
        }
        .ignoresSafeArea()
    }
}

/// 普通内容卡片。实体表面保持列表和数据内容清晰，避免大量毛玻璃造成的视觉与渲染负担。
struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(DesignSystem.cardPadding)
            .background {
                ZStack {
                    DesignSystem.cardBackground
                    LinearGradient(
                        colors: [.white.opacity(0.10), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.48), DesignSystem.borderColor, DesignSystem.borderColor.opacity(0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.025), radius: 4, x: 0, y: 1)
            .shadow(color: .black.opacity(0.045), radius: 14, x: 0, y: 7)
    }
}

/// 用于金额和预算等关键摘要的高层级卡片。
struct HeroCard: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        content
            .padding(DesignSystem.space24)
            .background {
                ZStack {
                    DesignSystem.cardBackground
                    LinearGradient(
                        colors: [accent.opacity(0.16), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    RadialGradient(
                        colors: [.white.opacity(0.20), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 240
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.heroCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.heroCornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.60), accent.opacity(0.24), accent.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.035), radius: 5, x: 0, y: 2)
            .shadow(color: accent.opacity(0.11), radius: 20, x: 0, y: 10)
    }
}

/// 统一轻触反馈；系统“减少动态效果”开启时只保留透明度变化。
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(reduceMotion ? nil : DesignSystem.quickAnimation, value: configuration.isPressed)
    }
}

/// 悬浮主操作按钮使用更明显的压缩与旋转反馈，释放后由系统 Sheet 动画接管。
struct FloatingActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.88 : 1)
            .rotationEffect(.degrees(configuration.isPressed && !reduceMotion ? 8 : 0))
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(reduceMotion ? nil : DesignSystem.emphasisAnimation, value: configuration.isPressed)
    }
}

/// 页面内容按层级轻柔进入，适合 Sheet 和首屏关键区块；减少动态效果时立即呈现。
struct SoftReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let delay: Double
    let distance: CGFloat
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible || reduceMotion ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : distance)
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.985)
            .onAppear {
                guard !reduceMotion else {
                    isVisible = true
                    return
                }
                withAnimation(DesignSystem.pageAnimation.delay(delay)) {
                    isVisible = true
                }
            }
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCard())
    }

    func heroCard(accent: Color = DesignSystem.primaryColor) -> some View {
        modifier(HeroCard(accent: accent))
    }

    func softReveal(delay: Double = 0, distance: CGFloat = 12) -> some View {
        modifier(SoftReveal(delay: delay, distance: distance))
    }
}
