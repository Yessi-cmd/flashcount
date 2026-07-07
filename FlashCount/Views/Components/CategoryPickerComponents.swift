import SwiftUI

struct CategorySelectionTile: View {
    let category: Category
    let selectedCategory: Category?
    let hasChildren: Bool
    let iconSize: Font
    let circleSize: CGFloat
    let minHeight: CGFloat
    let onSelect: () -> Void
    let onLongPress: () -> Void

    @State private var isPressing = false
    @State private var didStartPressFeedback = false

    private var rootName: String {
        category.rootCategoryName
    }

    private var isSelected: Bool {
        selectedCategory?.rootCategoryName == rootName
    }

    private var color: Color {
        Color(hex: Category.groupDefinition(for: rootName, isExpense: category.isExpense)?.colorHex ?? category.colorHex)
    }

    private var icon: String {
        Category.groupDefinition(for: rootName, isExpense: category.isExpense)?.icon ?? category.icon
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(isSelected ? color.opacity(0.18) : DesignSystem.softFill)
                        .frame(width: circleSize, height: circleSize)
                        .overlay {
                            if hasChildren && isPressing {
                                Circle()
                                    .stroke(color.opacity(0.26), lineWidth: 6)
                                    .scaleEffect(1.14)
                            }
                        }

                    if isSelected {
                        Circle()
                            .stroke(color, lineWidth: 2)
                            .frame(width: circleSize, height: circleSize)
                    }

                    Image(systemName: icon)
                        .font(iconSize)
                        .foregroundStyle(color)
                }

                if hasChildren {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(color)
                        .frame(width: 16, height: 16)
                        .background(.thinMaterial)
                        .clipShape(Circle())
                        .offset(x: 2, y: -2)
                }
            }

            Text(rootName)
                .font(.caption2)
                .foregroundStyle(isSelected ? DesignSystem.textPrimary : DesignSystem.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minHeight: minHeight)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .scaleEffect(isPressing ? 0.92 : 1)
        .opacity(isPressing ? 0.88 : 1)
        .animation(.spring(response: 0.18, dampingFraction: 0.78), value: isPressing)
        .onLongPressGesture(
            minimumDuration: 0.15,
            maximumDistance: 34,
            pressing: { pressing in
                updatePressingState(pressing)
            },
            perform: {
                isPressing = false
                didStartPressFeedback = false
                onLongPress()
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasChildren ? "\(rootName)，包含小类" : rootName)
        .accessibilityValue(isSelected ? "已选中" : "未选中")
        .accessibilityHint(hasChildren ? "长按选择小类" : "")
        .accessibilityAddTraits(.isButton)
    }

    private func updatePressingState(_ pressing: Bool) {
        guard hasChildren else {
            isPressing = false
            didStartPressFeedback = false
            return
        }

        isPressing = pressing
        if pressing {
            if !didStartPressFeedback {
                HapticManager.selection()
                didStartPressFeedback = true
            }
        } else {
            didStartPressFeedback = false
        }
    }
}

struct CategoryWheelOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let parentCategory: Category
    let children: [Category]
    let selectedCategory: Category?
    let onSelectParent: () -> Void
    let onSelectChild: (Category) -> Void
    let onDismiss: () -> Void

    @State private var isVisible = false
    @State private var isClosing = false

    private var usesGridLayout: Bool {
        children.count > 8
    }

    private var visibleChildren: [Category] {
        usesGridLayout ? children : Array(children.prefix(8))
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 72, maximum: 92), spacing: 10)]
    }

    private var parentName: String {
        parentCategory.rootCategoryName
    }

    private var parentColor: Color {
        Color(hex: Category.groupDefinition(for: parentName, isExpense: parentCategory.isExpense)?.colorHex ?? parentCategory.colorHex)
    }

    private var parentIcon: String {
        Category.groupDefinition(for: parentName, isExpense: parentCategory.isExpense)?.icon ?? parentCategory.icon
    }

    private var isParentSelected: Bool {
        selectedCategory?.id == parentCategory.id
    }

    var body: some View {
        GeometryReader { proxy in
            let wheelSize = wheelSize(for: proxy.size)
            let containerSize = containerSize(for: proxy.size, wheelSize: wheelSize)

            ZStack {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(isVisible ? 1 : 0)
                    Color.black.opacity(isVisible ? 0.22 : 0)
                }
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        HapticManager.selection()
                        closeThen(onDismiss)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("关闭分类选择")
                    .accessibilityAddTraits(.isButton)

                ZStack {
                    menuContent(wheelSize: wheelSize)
                }
                .overlay(alignment: .topTrailing) {
                    closeButton
                        .padding(8)
                        .scaleEffect(isVisible || reduceMotion ? 1 : 0.78)
                        .opacity(isVisible ? 1 : 0)
                        .animation(presentationAnimation, value: isVisible)
                }
                .frame(width: containerSize.width, height: containerSize.height)
                .scaleEffect(isVisible || reduceMotion ? 1 : 0.9)
                .offset(y: isVisible || reduceMotion ? 0 : 18)
                .blur(radius: isVisible || reduceMotion ? 0 : 8)
                .opacity(isVisible ? 1 : 0)
                .animation(presentationAnimation, value: isVisible)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .allowsHitTesting(!isClosing)
            }
            .accessibilityAction(.escape) {
                closeThen(onDismiss)
            }
        }
        .onAppear {
            withAnimation(presentationAnimation) {
                isVisible = true
            }
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94)),
            removal: .opacity
        ))
        .ignoresSafeArea()
    }

    private var closeButton: some View {
        Button {
            HapticManager.selection()
            closeThen(onDismiss)
        } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(DesignSystem.textSecondary)
                .frame(width: 32, height: 32)
                .background(.thinMaterial)
                .clipShape(Circle())
                .overlay(Circle().stroke(DesignSystem.borderColor, lineWidth: 1))
        }
        .buttonStyle(CategoryWheelPressButtonStyle())
        .accessibilityLabel("关闭分类选择")
    }

    @ViewBuilder
    private func menuContent(wheelSize: CGFloat) -> some View {
        if usesGridLayout {
            compactGridMenu(wheelSize: wheelSize)
        } else {
            radialWheel(wheelSize: wheelSize)
        }
    }

    private func radialWheel(wheelSize: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
                .overlay(Circle().fill(parentColor.opacity(isVisible ? 0.08 : 0)))
                .overlay(Circle().stroke(parentColor.opacity(0.26), lineWidth: 1))
                .shadow(color: parentColor.opacity(0.18), radius: 26, x: 0, y: 18)
                .shadow(color: .black.opacity(0.12), radius: 22, x: 0, y: 12)
                .scaleEffect(isVisible || reduceMotion ? 1 : 0.74)
                .opacity(isVisible ? 1 : 0)

            ForEach(Array(visibleChildren.enumerated()), id: \.element.id) { index, child in
                wheelChildButton(child, wheelSize: wheelSize)
                    .scaleEffect(isVisible || reduceMotion ? 1 : 0.56)
                    .opacity(isVisible ? 1 : 0)
                    .rotationEffect(.degrees(isVisible || reduceMotion ? 0 : -8))
                    .offset(childOffset(for: index, total: visibleChildren.count, wheelSize: wheelSize))
                    .animation(itemAnimation(for: index), value: isVisible)
            }

            parentButton(wheelSize: wheelSize)
        }
    }

    private func compactGridMenu(wheelSize: CGFloat) -> some View {
        VStack(spacing: 12) {
            parentButton(wheelSize: wheelSize)

            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 10) {
                    ForEach(Array(visibleChildren.enumerated()), id: \.element.id) { index, child in
                        wheelChildButton(child, wheelSize: wheelSize)
                            .scaleEffect(isVisible || reduceMotion ? 1 : 0.92)
                            .opacity(isVisible ? 1 : 0)
                            .animation(itemAnimation(for: index), value: isVisible)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                        .fill(parentColor.opacity(isVisible ? 0.08 : 0))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                        .stroke(parentColor.opacity(0.26), lineWidth: 1)
                )
        }
        .shadow(color: parentColor.opacity(0.18), radius: 26, x: 0, y: 18)
        .shadow(color: .black.opacity(0.12), radius: 22, x: 0, y: 12)
    }

    private func parentButton(wheelSize: CGFloat) -> some View {
        Button {
            HapticManager.selection()
            closeThen(onSelectParent)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: parentIcon)
                    .font(.title3)
                Text(parentName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("大类")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.textTertiary)
            }
            .foregroundStyle(parentColor)
            .frame(width: centerButtonSize(for: wheelSize), height: centerButtonSize(for: wheelSize))
            .background {
                Circle()
                    .fill(.thinMaterial)
                    .overlay(Circle().fill(parentColor.opacity(isParentSelected ? 0.18 : 0.1)))
            }
            .clipShape(Circle())
            .overlay(Circle().stroke(parentColor.opacity(isParentSelected ? 0.6 : 0.32), lineWidth: isParentSelected ? 1.4 : 1))
            .overlay(alignment: .topTrailing) {
                if isParentSelected {
                    selectedBadge(color: parentColor)
                        .offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(CategoryWheelPressButtonStyle())
        .scaleEffect(isVisible || reduceMotion ? 1 : 0.78)
        .opacity(isVisible ? 1 : 0)
        .animation(presentationAnimation, value: isVisible)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(parentName)，大类")
        .accessibilityValue(isParentSelected ? "已选中" : "未选中")
    }

    private func wheelChildButton(_ child: Category, wheelSize: CGFloat) -> some View {
        let isSelected = selectedCategory?.id == child.id
        let color = Color(hex: child.colorHex)
        let buttonSize = childButtonSize(for: wheelSize)

        return Button {
            HapticManager.selection()
            closeThen {
                onSelectChild(child)
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: child.icon)
                    .font(.caption.weight(.semibold))
                Text(child.name)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(color)
            .frame(width: buttonSize.width, height: buttonSize.height)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? color.opacity(0.18) : DesignSystem.softFill.opacity(0.72))
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color.opacity(0.7) : DesignSystem.borderColor, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    selectedBadge(color: color)
                        .offset(x: 5, y: -5)
                }
            }
            .shadow(color: isSelected ? color.opacity(0.18) : .black.opacity(0.08), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(CategoryWheelPressButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(child.name)，\(parentName)")
        .accessibilityValue(isSelected ? "已选中" : "未选中")
    }

    private func selectedBadge(color: Color) -> some View {
        Image(systemName: "checkmark")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(color)
            .clipShape(Circle())
            .shadow(color: color.opacity(0.28), radius: 6, x: 0, y: 3)
            .accessibilityHidden(true)
    }

    private func closeThen(_ action: @escaping () -> Void) {
        guard !isClosing else { return }
        isClosing = true

        withAnimation(dismissAnimation) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
            action()
        }
    }

    private func wheelSize(for size: CGSize) -> CGFloat {
        let width = max(size.width - 48, 248)
        let height = max(size.height - 168, 248)
        return min(296, width, height)
    }

    private func containerSize(for size: CGSize, wheelSize: CGFloat) -> CGSize {
        guard usesGridLayout else {
            return CGSize(width: wheelSize, height: wheelSize)
        }

        let width = min(max(size.width - 40, 280), 340)
        let height = min(max(size.height - 160, 320), 440)
        return CGSize(width: width, height: height)
    }

    private func centerButtonSize(for wheelSize: CGFloat) -> CGFloat {
        wheelSize < 280 ? 78 : 84
    }

    private func childButtonSize(for wheelSize: CGFloat) -> CGSize {
        wheelSize < 280
            ? CGSize(width: 68, height: 54)
            : CGSize(width: 72, height: 56)
    }

    private var presentationAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.14)
            : .spring(response: 0.24, dampingFraction: 0.84, blendDuration: 0.04)
    }

    private var dismissAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.1)
            : .spring(response: 0.14, dampingFraction: 0.92)
    }

    private var dismissDelay: TimeInterval {
        reduceMotion ? 0.06 : 0.1
    }

    private func itemAnimation(for index: Int) -> Animation {
        if reduceMotion {
            return .easeOut(duration: 0.16).delay(Double(index) * 0.008)
        }

        return .spring(response: 0.34, dampingFraction: 0.72, blendDuration: 0.06)
            .delay(Double(index) * 0.018)
    }

    private func childOffset(for index: Int, total: Int, wheelSize: CGFloat) -> CGSize {
        if reduceMotion || isVisible {
            return childOffset(index: index, total: total, wheelSize: wheelSize)
        }

        return .zero
    }

    private func childOffset(index: Int, total: Int, wheelSize: CGFloat) -> CGSize {
        guard total > 0 else { return .zero }
        let angle = Angle.degrees(-90 + Double(index) * 360 / Double(total)).radians
        let radius = wheelSize * 0.35
        return CGSize(
            width: CGFloat(cos(angle)) * radius,
            height: CGFloat(sin(angle)) * radius
        )
    }
}

private struct CategoryWheelPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.14, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
