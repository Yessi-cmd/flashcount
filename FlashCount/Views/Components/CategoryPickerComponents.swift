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
            ZStack {
                ZStack {
                    Circle()
                        .fill(isSelected ? color.opacity(0.18) : DesignSystem.softFill)
                        .frame(width: circleSize, height: circleSize)
                        .overlay {
                            if hasChildren && isPressing {
                                Circle()
                                    .stroke(color.opacity(0.32), lineWidth: 2)
                                    .scaleEffect(1.08)
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

            }

            HStack(spacing: 3) {
                Text(rootName)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if hasChildren {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(DesignSystem.textTertiary)
                }
            }
            .foregroundStyle(isSelected ? DesignSystem.textPrimary : DesignSystem.textSecondary)
        }
        .frame(minHeight: minHeight)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .scaleEffect(isPressing ? 0.96 : 1)
        .opacity(isPressing ? 0.94 : 1)
        .animation(.easeOut(duration: 0.12), value: isPressing)
        .onLongPressGesture(
            minimumDuration: 0.22,
            maximumDistance: 34,
            pressing: { pressing in
                updatePressingState(pressing)
            },
            perform: {
                isPressing = false
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
            return
        }

        isPressing = pressing
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
    @State private var dialedChildIndex: Int?

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
            let wheelSize = min(proxy.size.width - 32, proxy.size.height - 120, 350)

            ZStack {
                Color.black
                    .opacity(isVisible ? 0.3 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        closeThen(onDismiss)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("关闭分类选择")
                    .accessibilityAddTraits(.isButton)

                categoryWheel(size: wheelSize)
                    .scaleEffect(isVisible || reduceMotion ? 1 : 0.74)
                    .rotationEffect(.degrees(isVisible || reduceMotion ? 0 : -7))
                    .opacity(isVisible ? 1 : 0)
                    .allowsHitTesting(!isClosing)
            }
            .animation(presentationAnimation, value: isVisible)
            .accessibilityAction(.escape) {
                closeThen(onDismiss)
            }
        }
        .onAppear {
            withAnimation(presentationAnimation) {
                isVisible = true
            }
        }
        .transition(.opacity)
        .ignoresSafeArea()
    }

    private func categoryWheel(size: CGFloat) -> some View {
        let count = max(children.count, 1)
        let sectorAngle = 360 / Double(count)
        let labelRadius = size * 0.345

        return ZStack {
            Circle()
                .fill(.regularMaterial)
                .overlay(Circle().fill(parentColor.opacity(0.06)))

            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                let middleAngle = -90 + Double(index) * sectorAngle
                let startAngle = middleAngle - sectorAngle / 2 + 1.2
                let endAngle = middleAngle + sectorAngle / 2 - 1.2
                let childColor = Color(hex: child.colorHex)
                let isSelected = selectedCategory?.id == child.id
                let isDialed = dialedChildIndex == index
                let sector = AnnularSector(
                    startAngle: .degrees(startAngle),
                    endAngle: .degrees(endAngle),
                    innerRadiusRatio: 0.39
                )

                ZStack {
                    sector
                        .fill(childColor.opacity(isDialed ? 0.36 : (isSelected ? 0.3 : 0.14)))
                        .overlay {
                            sector.stroke(
                                isDialed || isSelected ? childColor.opacity(0.82) : Color.white.opacity(0.34),
                                lineWidth: isDialed || isSelected ? 1.5 : 0.8
                            )
                        }

                    VStack(spacing: 5) {
                        Image(systemName: child.icon)
                            .font(.system(size: 16, weight: .semibold))
                        Text(child.name)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.72)
                    }
                    .foregroundStyle(isDialed || isSelected ? childColor : DesignSystem.textPrimary)
                    .frame(width: max(54, size * 0.2))
                    .scaleEffect(isDialed ? 1.06 : 1)
                    .offset(
                        x: CGFloat(cos(Angle.degrees(middleAngle).radians)) * labelRadius,
                        y: CGFloat(sin(Angle.degrees(middleAngle).radians)) * labelRadius
                    )
                }
                .frame(width: size, height: size)
                .contentShape(sector)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(child.name)，\(parentName)")
                .accessibilityValue(isSelected ? "已选中" : "未选中")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    HapticManager.selection()
                    closeThen { onSelectChild(child) }
                }
            }

            Button {
                HapticManager.selection()
                closeThen(onSelectParent)
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: parentIcon)
                        .font(.system(size: 22, weight: .semibold))
                    Text(parentName)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text("使用大类")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DesignSystem.textTertiary)
                }
                .foregroundStyle(parentColor)
                .frame(width: size * 0.35, height: size * 0.35)
                .background(.thickMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(parentColor.opacity(isParentSelected ? 0.72 : 0.32), lineWidth: isParentSelected ? 2 : 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 7)
            }
            .buttonStyle(CategoryWheelPressButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(parentName)，大类")
            .accessibilityValue(isParentSelected ? "已选中" : "未选中")
        }
        .frame(width: size, height: size)
        .simultaneousGesture(dialGesture(size: size))
        .clipShape(Circle())
        .overlay {
            Circle().stroke(Color.white.opacity(0.42), lineWidth: 1)
        }
        .shadow(color: parentColor.opacity(0.15), radius: 26, x: 0, y: 14)
        .shadow(color: .black.opacity(0.18), radius: 22, x: 0, y: 12)
    }

    private func dialGesture(size: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard let index = childIndex(at: value.location, wheelSize: size) else {
                    dialedChildIndex = nil
                    return
                }

                guard dialedChildIndex != index else { return }
                dialedChildIndex = index
                HapticManager.selection()
            }
            .onEnded { value in
                let index = childIndex(at: value.location, wheelSize: size) ?? dialedChildIndex
                dialedChildIndex = nil
                guard let index, children.indices.contains(index) else { return }
                closeThen { onSelectChild(children[index]) }
            }
    }

    private func childIndex(at location: CGPoint, wheelSize: CGFloat) -> Int? {
        guard !children.isEmpty else { return nil }
        let center = CGPoint(x: wheelSize / 2, y: wheelSize / 2)
        let deltaX = location.x - center.x
        let deltaY = location.y - center.y
        let radius = hypot(deltaX, deltaY)
        let innerRadius = wheelSize * 0.195
        let outerRadius = wheelSize * 0.5
        guard radius >= innerRadius, radius <= outerRadius else { return nil }

        let angle = atan2(deltaY, deltaX) * 180 / .pi
        let normalized = (angle + 90 + 360).truncatingRemainder(dividingBy: 360)
        let sectorAngle = 360 / Double(children.count)
        return Int((normalized + sectorAngle / 2) / sectorAngle) % children.count
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

    private var presentationAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(response: 0.28, dampingFraction: 0.86, blendDuration: 0.04)
    }

    private var dismissAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.08)
            : .easeIn(duration: 0.13)
    }

    private var dismissDelay: TimeInterval {
        reduceMotion ? 0.05 : 0.13
    }
}

private struct AnnularSector: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadiusRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * innerRadiusRatio
        var path = Path()

        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}

private struct CategoryWheelPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
