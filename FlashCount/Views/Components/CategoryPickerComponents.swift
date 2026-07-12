import SwiftUI

struct CategorySelectionTile: View {
    let category: Category
    let selectedCategory: Category?
    let hasChildren: Bool
    let iconSize: Font
    let circleSize: CGFloat
    let minHeight: CGFloat
    let onSelect: (CGRect?) -> Void
    let onLongPress: (CGRect?) -> Void

    @State private var isPressing = false
    @State private var globalFrame: CGRect?

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
                Circle()
                    .fill(color.opacity(isSelected ? 0.18 : 0.10))
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
                        .stroke(color.opacity(0.82), lineWidth: 1.8)
                        .frame(width: circleSize, height: circleSize)
                }

                Image(systemName: icon)
                    .font(iconSize)
                    .foregroundStyle(color)
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
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        globalFrame = proxy.frame(in: .global)
                    }
                    .onChange(of: proxy.frame(in: .global)) { _, newFrame in
                        globalFrame = newFrame
                    }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if hasChildren {
                onLongPress(globalFrame)
            } else {
                onSelect(globalFrame)
            }
        }
        .scaleEffect(isPressing ? 0.96 : 1)
        .opacity(isPressing ? 0.94 : 1)
        .animation(.easeOut(duration: 0.12), value: isPressing)
        .onLongPressGesture(
            minimumDuration: 0.35,
            maximumDistance: 34,
            pressing: { pressing in
                updatePressingState(pressing)
            },
            perform: {
                isPressing = false
                onLongPress(globalFrame)
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasChildren ? "\(rootName)，包含小类" : rootName)
        .accessibilityValue(isSelected ? "已选中" : "未选中")
        .accessibilityHint(hasChildren ? "点按选择具体分类" : "")
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    let parentCategory: Category
    let children: [Category]
    let selectedCategory: Category?
    let sourceFrame: CGRect?
    let onSelectParent: () -> Void
    let onSelectChild: (Category) -> Void
    let onDismiss: () -> Void

    @State private var phase: PresentationPhase = .hidden
    @State private var isPresented = false
    @State private var labelsVisible = false
    @State private var dialedChildIndex: Int?
    @State private var selectionPulseIndex: Int?
    @State private var transitionTask: Task<Void, Never>?

    private enum PresentationPhase: Equatable {
        case hidden
        case opening
        case open
        case selecting(Int)
        case closing

        var acceptsInput: Bool {
            self == .opening || self == .open
        }
    }

    private var parentName: String {
        parentCategory.rootCategoryName
    }

    private var parentIcon: String {
        Category.groupDefinition(for: parentName, isExpense: parentCategory.isExpense)?.icon ?? parentCategory.icon
    }

    private var parentColor: Color {
        Color(hex: Category.groupDefinition(for: parentName, isExpense: parentCategory.isExpense)?.colorHex ?? parentCategory.colorHex)
    }

    private var isParentSelected: Bool {
        selectedCategory?.id == parentCategory.id
    }

    var body: some View {
        GeometryReader { proxy in
            let containerFrame = proxy.frame(in: .global)
            let sourceOffset = sourceOffset(in: proxy, containerFrame: containerFrame)

            ZStack {
                Color.black
                    .opacity(isPresented ? (colorScheme == .dark ? 0.38 : 0.24) : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissThen(onDismiss)
                    }
                    .accessibilityHidden(true)

                if dynamicTypeSize.isAccessibilitySize {
                    accessibilityPicker(sourceOffset: sourceOffset)
                } else {
                    wheel(in: proxy, sourceOffset: sourceOffset)
                }
            }
            .accessibilityAction(.escape) {
                dismissThen(onDismiss)
            }
        }
        .onAppear {
            present()
        }
        .onDisappear {
            transitionTask?.cancel()
        }
        .transition(.identity)
        .ignoresSafeArea()
    }

    private func wheel(in proxy: GeometryProxy, sourceOffset: CGSize) -> some View {
        let wheelSize = CategoryWheelLayout.preferredSize(
            itemCount: children.count,
            availableWidth: proxy.size.width - 32,
            availableHeight: proxy.size.height - 120
        )
        let layout = CategoryWheelLayout(itemCount: children.count, size: wheelSize)

        return ZStack {
            CategoryWheelSurface(
                layout: layout,
                children: children,
                selectedCategoryID: selectedCategory?.id,
                activeIndex: dialedChildIndex ?? selectionPulseIndex
            )
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.34 : 0.15),
                radius: 22,
                x: 0,
                y: 12
            )

            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                categoryLabel(child, index: index, layout: layout)
            }

            centerHub(size: wheelSize)
        }
        .frame(width: wheelSize, height: wheelSize)
        .contentShape(Circle())
        .simultaneousGesture(dialGesture(layout: layout))
        .scaleEffect(isPresented || reduceMotion ? 1 : 0.78)
        .rotationEffect(.degrees(isPresented || reduceMotion ? 0 : -8))
        .offset(
            x: isPresented || reduceMotion ? 0 : sourceOffset.width,
            y: isPresented || reduceMotion ? 0 : sourceOffset.height
        )
        .opacity(isPresented ? 1 : 0)
        .allowsHitTesting(phase.acceptsInput)
    }

    private func categoryLabel(_ child: Category, index: Int, layout: CategoryWheelLayout) -> some View {
        let isActive = dialedChildIndex == index || selectionPulseIndex == index
        let isSelected = selectedCategory?.id == child.id
        let childColor = Color(hex: child.colorHex)
        let point = layout.labelPoint(for: index, radialOffset: isActive ? 3 : 0)

        return VStack(spacing: 5) {
            Image(systemName: child.icon)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.monochrome)
            Text(child.name)
                .font(.system(size: layout.itemCount >= 8 ? 10 : 11, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.68)
        }
        .foregroundStyle(isActive || isSelected ? childColor : DesignSystem.textPrimary)
        .frame(width: layout.itemCount >= 8 ? 66 : 78)
        .scaleEffect(selectionPulseIndex == index ? 1.14 : isActive ? 1.07 : 1)
        .position(point)
        .opacity(labelsVisible ? (dialedChildIndex == nil || isActive ? 1 : 0.68) : 0)
        .offset(y: labelsVisible ? 0 : 7)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.31, dampingFraction: 0.79)
                    .delay(Double(index) * 0.018),
            value: labelsVisible
        )
        .animation(.easeOut(duration: 0.11), value: isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(child.name)，\(parentName)")
        .accessibilityValue(isSelected ? "已选中" : "未选中")
        .accessibilityAddTraits(.isButton)
        .accessibilitySortPriority(Double(children.count - index))
        .accessibilityAction {
            confirmChild(at: index)
        }
    }

    private func centerHub(size: CGFloat) -> some View {
        Button {
            guard phase.acceptsInput else { return }
            HapticManager.selection()
            selectionPulseIndex = nil
            phase = .selecting(-1)
            scheduleSelection {
                onSelectParent()
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: parentIcon)
                    .font(.system(size: 23, weight: .semibold))
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
            .overlay {
                Circle()
                    .stroke(parentColor.opacity(isParentSelected ? 0.64 : 0.24), lineWidth: isParentSelected ? 1.6 : 1)
                    .padding(2)
            }
        }
        .buttonStyle(CategoryWheelHubButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(parentName)，大类")
        .accessibilityValue(isParentSelected ? "已选中" : "未选中")
        .accessibilitySortPriority(Double(children.count + 1))
    }

    private func accessibilityPicker(sourceOffset: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: parentIcon)
                    .font(.headline)
                    .foregroundStyle(parentColor)
                Text("选择\(parentName)分类")
                    .font(.headline)
                    .foregroundStyle(DesignSystem.textPrimary)
                Spacer()
            }
            .padding(16)

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    accessibleCategoryButton(
                        title: "使用大类",
                        icon: parentIcon,
                        color: parentColor,
                        isSelected: isParentSelected
                    ) {
                        HapticManager.selection()
                        scheduleSelection(action: onSelectParent)
                    }

                    ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                        accessibleCategoryButton(
                            title: child.name,
                            icon: child.icon,
                            color: Color(hex: child.colorHex),
                            isSelected: selectedCategory?.id == child.id
                        ) {
                            confirmChild(at: index)
                        }
                    }
                }
                .padding(14)
            }
        }
        .frame(maxWidth: 360, maxHeight: 560)
        .background(CategoryWheelPalette.porcelainBase)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CategoryWheelPalette.rim, lineWidth: 1.2)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.16), radius: 22, x: 0, y: 12)
        .padding(.horizontal, 24)
        .scaleEffect(isPresented || reduceMotion ? 1 : 0.92)
        .offset(
            x: isPresented || reduceMotion ? 0 : sourceOffset.width * 0.35,
            y: isPresented || reduceMotion ? 0 : sourceOffset.height * 0.35
        )
        .opacity(isPresented ? 1 : 0)
        .allowsHitTesting(phase.acceptsInput)
    }

    private func accessibleCategoryButton(
        title: String,
        icon: String,
        color: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 28)
                    .foregroundStyle(color)
                Text(title)
                    .foregroundStyle(DesignSystem.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(color)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(color.opacity(isSelected ? 0.16 : 0.075))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func dialGesture(layout: CategoryWheelLayout) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard phase.acceptsInput else { return }
                let index = layout.index(at: value.location)
                guard dialedChildIndex != index else { return }
                dialedChildIndex = index
                if index != nil {
                    HapticManager.selection()
                }
            }
            .onEnded { value in
                guard phase.acceptsInput else { return }
                let index = layout.index(at: value.location) ?? dialedChildIndex
                dialedChildIndex = nil
                guard let index, children.indices.contains(index) else { return }
                confirmChild(at: index)
            }
    }

    private func confirmChild(at index: Int) {
        guard phase.acceptsInput, children.indices.contains(index) else { return }
        phase = .selecting(index)
        selectionPulseIndex = index
        scheduleSelection {
            onSelectChild(children[index])
        }
    }

    private func present() {
        transitionTask?.cancel()
        phase = .opening

        withAnimation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.05)
        ) {
            isPresented = true
        }

        labelsVisible = true
        transitionTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: reduceMotion ? 120_000_000 : 360_000_000)
            } catch {
                return
            }
            guard phase == .opening else { return }
            phase = .open
        }
    }

    private func scheduleSelection(action: @escaping () -> Void) {
        transitionTask?.cancel()
        transitionTask = Task { @MainActor in
            if !reduceMotion {
                do {
                    try await Task.sleep(nanoseconds: 90_000_000)
                } catch {
                    return
                }
            }
            beginClosing(action: action)
        }
    }

    private func dismissThen(_ action: @escaping () -> Void) {
        guard phase != .closing && phase != .hidden else { return }
        transitionTask?.cancel()
        beginClosing(action: action)
    }

    private func beginClosing(action: @escaping () -> Void) {
        phase = .closing
        dialedChildIndex = nil
        labelsVisible = false

        withAnimation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .easeInOut(duration: 0.18)
        ) {
            isPresented = false
        }

        transitionTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: reduceMotion ? 120_000_000 : 180_000_000)
            } catch {
                return
            }
            phase = .hidden
            action()
        }
    }

    private func sourceOffset(in proxy: GeometryProxy, containerFrame: CGRect) -> CGSize {
        guard let sourceFrame else { return .zero }
        let sourceCenter = CGPoint(
            x: sourceFrame.midX - containerFrame.minX,
            y: sourceFrame.midY - containerFrame.minY
        )
        let destinationCenter = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
        return CGSize(
            width: sourceCenter.x - destinationCenter.x,
            height: sourceCenter.y - destinationCenter.y
        )
    }
}

private struct CategoryWheelSurface: View {
    @Environment(\.colorScheme) private var colorScheme

    let layout: CategoryWheelLayout
    let children: [Category]
    let selectedCategoryID: UUID?
    let activeIndex: Int?

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            let outerRect = circleRect(radius: layout.outerRadius)
            let innerRect = circleRect(radius: layout.innerRadius)

            context.fill(
                Path(ellipseIn: outerRect),
                with: .linearGradient(
                    Gradient(colors: [CategoryWheelPalette.porcelainHighlight, CategoryWheelPalette.porcelainBase]),
                    startPoint: CGPoint(x: layout.size * 0.2, y: 0),
                    endPoint: CGPoint(x: layout.size * 0.8, y: layout.size)
                )
            )

            for (index, child) in children.enumerated() {
                let isActive = activeIndex == index
                let isSelected = selectedCategoryID == child.id
                let color = Color(hex: child.colorHex)
                let path = layout.sectorPath(for: index, radialOffset: isActive ? 2.5 : 0)
                let start = layout.labelPoint(for: index, radialOffset: -layout.labelRadius * 0.45)
                let end = layout.labelPoint(for: index, radialOffset: layout.labelRadius * 0.55)

                context.fill(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [
                            color.opacity(isActive ? 0.28 : isSelected ? 0.18 : 0.10),
                            color.opacity(isActive ? 0.16 : isSelected ? 0.10 : 0.035)
                        ]),
                        startPoint: start,
                        endPoint: end
                    )
                )
                context.stroke(
                    path,
                    with: .color(isActive || isSelected ? color.opacity(0.62) : CategoryWheelPalette.separator),
                    lineWidth: isActive ? 1.45 : isSelected ? 1.2 : 0.85
                )
            }

            context.fill(
                Path(ellipseIn: innerRect),
                with: .radialGradient(
                    Gradient(colors: [CategoryWheelPalette.porcelainHighlight, CategoryWheelPalette.porcelainBase]),
                    center: CGPoint(x: innerRect.midX - innerRect.width * 0.12, y: innerRect.midY - innerRect.height * 0.14),
                    startRadius: 0,
                    endRadius: layout.innerRadius
                )
            )
            context.stroke(Path(ellipseIn: innerRect), with: .color(CategoryWheelPalette.innerRim), lineWidth: 2)
            context.stroke(Path(ellipseIn: outerRect), with: .color(CategoryWheelPalette.rim), lineWidth: 2.2)

            let highlightRect = outerRect.insetBy(dx: 3.2, dy: 3.2)
            context.stroke(
                Path(ellipseIn: highlightRect),
                with: .linearGradient(
                    Gradient(colors: [.white.opacity(colorScheme == .dark ? 0.10 : 0.72), .clear]),
                    startPoint: CGPoint(x: highlightRect.minX, y: highlightRect.minY),
                    endPoint: CGPoint(x: highlightRect.maxX, y: highlightRect.maxY)
                ),
                lineWidth: 1.1
            )
        }
        .frame(width: layout.size, height: layout.size)
    }

    private func circleRect(radius: CGFloat) -> CGRect {
        CGRect(
            x: layout.center.x - radius,
            y: layout.center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
    }
}

private enum CategoryWheelPalette {
    static let porcelainHighlight = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.17, green: 0.19, blue: 0.17, alpha: 1)
            : UIColor(red: 1.0, green: 0.994, blue: 0.978, alpha: 1)
    })

    static let porcelainBase = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.095, green: 0.11, blue: 0.10, alpha: 1)
            : UIColor(red: 0.955, green: 0.935, blue: 0.895, alpha: 1)
    })

    static let rim = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.48, green: 0.45, blue: 0.39, alpha: 0.55)
            : UIColor(red: 0.66, green: 0.61, blue: 0.52, alpha: 0.64)
    })

    static let innerRim = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.13)
            : UIColor.white.withAlphaComponent(0.88)
    })

    static let separator = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor(red: 0.70, green: 0.68, blue: 0.63, alpha: 0.38)
    })
}

private struct CategoryWheelHubButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
