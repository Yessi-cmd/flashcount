import SwiftUI

/// 外观偏好，存在 `@AppStorage("appearance")`。`.system` 映射为 nil，
/// 即交回系统决定；本 App 默认浅色。
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
        static let supportingLabel = Font.system(.caption, design: .rounded, weight: .medium)
        static let amount = Font.system(.largeTitle, design: .rounded, weight: .bold)
        static let keypadDigit = Font.system(.title3, design: .rounded, weight: .medium)
        static let wheelIcon = Font.system(.body, design: .rounded, weight: .semibold)
        static let wheelLabel = Font.system(.caption, design: .rounded, weight: .medium)
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

    static let primaryColor = Color(uiColor: UIColor { traits in
        let highContrast = traits.accessibilityContrast == .high
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: highContrast ? 0.53 : 0.36, green: highContrast ? 0.82 : 0.56, blue: highContrast ? 0.70 : 0.48, alpha: 1)
        }
        return UIColor(red: highContrast ? 0.15 : 0.306, green: highContrast ? 0.34 : 0.463, blue: highContrast ? 0.28 : 0.416, alpha: 1)
    })
    static let incomeColor = Color(uiColor: UIColor { traits in
        let highContrast = traits.accessibilityContrast == .high
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: highContrast ? 0.48 : 0.36, green: highContrast ? 0.84 : 0.53, blue: highContrast ? 0.68 : 0.48, alpha: 1)
        }
        return UIColor(red: highContrast ? 0.10 : 0.357, green: highContrast ? 0.39 : 0.533, blue: highContrast ? 0.25 : 0.482, alpha: 1)
    })
    static let expenseColor = Color(uiColor: UIColor { traits in
        let highContrast = traits.accessibilityContrast == .high
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: highContrast ? 1.00 : 0.72, green: highContrast ? 0.55 : 0.44, blue: highContrast ? 0.50 : 0.41, alpha: 1)
        }
        return UIColor(red: highContrast ? 0.55 : 0.722, green: highContrast ? 0.16 : 0.435, blue: highContrast ? 0.13 : 0.412, alpha: 1)
    })
    static let warningColor = Color(uiColor: UIColor { traits in
        let highContrast = traits.accessibilityContrast == .high
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: highContrast ? 1.00 : 0.69, green: highContrast ? 0.80 : 0.54, blue: highContrast ? 0.38 : 0.31, alpha: 1)
        }
        return UIColor(red: highContrast ? 0.43 : 0.686, green: highContrast ? 0.25 : 0.537, blue: highContrast ? 0.02 : 0.314, alpha: 1)
    })
    static let dangerColor = Color(uiColor: UIColor { traits in
        let highContrast = traits.accessibilityContrast == .high
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: highContrast ? 1.00 : 0.72, green: highContrast ? 0.48 : 0.38, blue: highContrast ? 0.52 : 0.40, alpha: 1)
        }
        return UIColor(red: highContrast ? 0.54 : 0.722, green: highContrast ? 0.12 : 0.376, blue: highContrast ? 0.16 : 0.400, alpha: 1)
    })
    static let weekendColorHex = "#6E8797"
    static let weekendColor = Color(uiColor: UIColor { traits in
        let highContrast = traits.accessibilityContrast == .high
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: highContrast ? 0.68 : 0.43, green: highContrast ? 0.82 : 0.53, blue: highContrast ? 0.90 : 0.59, alpha: 1)
        }
        return UIColor(red: highContrast ? 0.14 : 0.431, green: highContrast ? 0.30 : 0.529, blue: highContrast ? 0.40 : 0.592, alpha: 1)
    })

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
        let highContrast = traits.accessibilityContrast == .high
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: highContrast ? 0.86 : 0.67, green: highContrast ? 0.90 : 0.72, blue: highContrast ? 0.87 : 0.69, alpha: 1)
        }
        return UIColor(red: highContrast ? 0.17 : 0.392, green: highContrast ? 0.23 : 0.439, blue: highContrast ? 0.20 : 0.416, alpha: 1)
    })

    static let textTertiary = Color(uiColor: UIColor { traits in
        let highContrast = traits.accessibilityContrast == .high
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: highContrast ? 0.76 : 0.47, green: highContrast ? 0.81 : 0.52, blue: highContrast ? 0.78 : 0.49, alpha: 1)
        }
        return UIColor(red: highContrast ? 0.29 : 0.537, green: highContrast ? 0.35 : 0.573, blue: highContrast ? 0.32 : 0.557, alpha: 1)
    })

    static let softFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.18, green: 0.25, blue: 0.22, alpha: 1)
        : UIColor(red: 0.91, green: 0.94, blue: 0.925, alpha: 1)
    })

    static let borderColor = Color(uiColor: UIColor { traits in
        let highContrast = traits.accessibilityContrast == .high
        if traits.userInterfaceStyle == .dark {
            return UIColor.white.withAlphaComponent(highContrast ? 0.34 : 0.22)
        }
        return UIColor(red: highContrast ? 0.47 : 0.875, green: highContrast ? 0.53 : 0.898, blue: highContrast ? 0.49 : 0.882, alpha: 1)
    })

    static let dividerColor = Color(uiColor: UIColor { traits in
        let highContrast = traits.accessibilityContrast == .high
        if traits.userInterfaceStyle == .dark {
            return UIColor.white.withAlphaComponent(highContrast ? 0.30 : 0.18)
        }
        return UIColor(red: highContrast ? 0.45 : 0.89, green: highContrast ? 0.51 : 0.91, blue: highContrast ? 0.47 : 0.898, alpha: 1)
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
    static let glassSelectionAnimation = Animation.spring(response: 0.42, dampingFraction: 0.82, blendDuration: 0.10)
    static let navigationAnimation = Animation.spring(response: 0.44, dampingFraction: 0.86, blendDuration: 0.08)
    static let pageAnimation = Animation.spring(response: 0.52, dampingFraction: 0.90, blendDuration: 0.10)
}

/// iOS 26 自定义导航与控制表面的统一 Liquid Glass 配置。
/// 内容修饰应在调用此修饰器前完成，确保系统能正确捕获最终外观。
/// 较早 SDK 将它编译为透明修饰器，以保持同一视图层级。
@available(iOS 26.0, *)
struct LiquidGlassSurface: ViewModifier {
    enum Shape {
        case roundedRectangle(CGFloat)
        case capsule
        case circle
    }

    let tint: Color?
    let shape: Shape
    let isInteractive: Bool
    let isClear: Bool

#if compiler(>=6.2)
    private var effect: Glass {
        let base: Glass = isClear ? .clear : .regular
        return base
            .tint(tint)
            .interactive(isInteractive)
    }
#endif

    @ViewBuilder
    func body(content: Content) -> some View {
#if compiler(>=6.2)
        switch shape {
        case .roundedRectangle(let cornerRadius):
            content
                .glassEffect(effect, in: .rect(cornerRadius: cornerRadius))
        case .capsule:
            content
                .glassEffect(effect, in: .capsule)
        case .circle:
            content
                .glassEffect(effect, in: .circle)
        }
#else
        content
#endif
    }
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

    @available(iOS 26.0, *)
    func liquidGlassSurface(
        tint: Color? = nil,
        shape: LiquidGlassSurface.Shape = .capsule,
        isInteractive: Bool = false,
        isClear: Bool = false
    ) -> some View {
        modifier(
            LiquidGlassSurface(
                tint: tint,
                shape: shape,
                isInteractive: isInteractive,
                isClear: isClear
            )
        )
    }
}
