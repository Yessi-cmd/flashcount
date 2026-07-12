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

    // MARK: - Typography

    /// The app uses rounded system faces for Latin text and numerals while
    /// retaining the system CJK fallback for legibility. Semantic sizes keep
    /// Dynamic Type behavior instead of scattering fixed point sizes.
    enum Typography {
        static let controlLabel = Font.system(.subheadline, design: .rounded, weight: .semibold)
        static let compactLabel = Font.system(.caption, design: .rounded, weight: .medium)
        static let compactLabelEmphasized = Font.system(.caption, design: .rounded, weight: .semibold)
        static let supportingLabel = Font.system(.caption2, design: .rounded, weight: .medium)
        static let amount = Font.system(size: 40, weight: .bold, design: .rounded)
        static let keypadDigit = Font.system(.title3, design: .rounded, weight: .medium)
        static let wheelIcon = Font.system(.body, design: .rounded, weight: .semibold)
        static let wheelLabel = Font.system(.caption2, design: .rounded, weight: .medium)
        static let wheelHubTitle = Font.system(.subheadline, design: .rounded, weight: .bold)
    }

    // MARK: - 品牌色

    /// B 方向主色。保留 ShapeStyle 类型兼容现有调用，但两端同色，不再产生渐变。
    static let primaryGradient = LinearGradient(
        colors: [Color(hex: "#4E766A"), Color(hex: "#4E766A")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 收入渐变
    static let incomeGradient = LinearGradient(
        colors: [Color(hex: "#5B887B"), Color(hex: "#5B887B")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 支出渐变
    static let expenseGradient = LinearGradient(
        colors: [Color(hex: "#B86F69"), Color(hex: "#B86F69")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 危险渐变
    static let dangerGradient = LinearGradient(
        colors: [Color(hex: "#B86066"), Color(hex: "#B86066")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 警告渐变
    static let warningGradient = LinearGradient(
        colors: [Color(hex: "#AF8950"), Color(hex: "#AF8950")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - 单色

    static let primaryColor = Color(hex: "#4E766A")
    static let incomeColor = Color(hex: "#5B887B")
    static let expenseColor = Color(hex: "#B86F69")
    static let warningColor = Color(hex: "#AF8950")
    static let dangerColor = Color(hex: "#B86066")

    static let surfaceBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.063, green: 0.090, blue: 0.078, alpha: 1)
        : UIColor(red: 0.953, green: 0.945, blue: 0.925, alpha: 1)
    })

    static let cardBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.094, green: 0.129, blue: 0.114, alpha: 1)
        : UIColor.white
    })

    static let textPrimary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.93, green: 0.95, blue: 0.94, alpha: 1)
        : UIColor(red: 0.149, green: 0.192, blue: 0.176, alpha: 1)
    })

    static let textSecondary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.67, green: 0.72, blue: 0.69, alpha: 1)
        : UIColor(red: 0.392, green: 0.439, blue: 0.416, alpha: 1)
    })

    static let textTertiary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.47, green: 0.52, blue: 0.49, alpha: 1)
        : UIColor(red: 0.537, green: 0.573, blue: 0.557, alpha: 1)
    })

    static let softFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.18, green: 0.25, blue: 0.22, alpha: 1)
        : UIColor(red: 0.91, green: 0.94, blue: 0.925, alpha: 1)
    })

    static let borderColor = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.09)
        : UIColor(red: 0.875, green: 0.898, blue: 0.882, alpha: 1)
    })

    static let dividerColor = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.10)
        : UIColor(red: 0.89, green: 0.91, blue: 0.898, alpha: 1)
    })

    // MARK: - Layout tokens

    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32
    static let cornerRadius: CGFloat = 15
    static let smallCornerRadius: CGFloat = 10
    static let heroCornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 17
    static let sectionSpacing: CGFloat = 18

    // MARK: - Motion tokens

    static let quickAnimation = Animation.easeOut(duration: 0.16)
    static let standardAnimation = Animation.easeInOut(duration: 0.24)
    static let emphasisAnimation = Animation.spring(response: 0.36, dampingFraction: 0.84)
    static let navigationAnimation = Animation.spring(response: 0.44, dampingFraction: 0.86, blendDuration: 0.08)
    static let pageAnimation = Animation.spring(response: 0.52, dampingFraction: 0.90, blendDuration: 0.10)
}

/// B 方向背景：暖灰底色叠加轻微顶部色层，不使用光晕或渐变。
struct AmbientBackground: View {
    let accent: Color

    var body: some View {
        ZStack {
            DesignSystem.surfaceBackground
            VStack(spacing: 0) {
                accent.opacity(0.055)
                    .frame(height: 210)
                Spacer(minLength: 0)
            }
        }
        .ignoresSafeArea()
    }
}

/// 普通内容卡片。实体表面保持列表和数据内容清晰，避免大量毛玻璃造成的视觉与渲染负担。
struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(DesignSystem.cardPadding)
            .background(DesignSystem.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .stroke(DesignSystem.borderColor.opacity(0.85), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.035), radius: 12, x: 0, y: 5)
    }
}

/// 用于金额和预算等关键摘要的高层级卡片。
struct HeroCard: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        content
            .padding(20)
            .background {
                ZStack {
                    DesignSystem.cardBackground
                    accent.opacity(0.03)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.heroCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.heroCornerRadius)
                    .stroke(DesignSystem.borderColor.opacity(0.9), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 13, x: 0, y: 6)
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

/// 主操作只保留快速压缩反馈，不再旋转或发光。
struct FloatingActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
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
