import SwiftUI

struct CategorySelectionTile: View {
    let category: Category
    let selectedCategory: Category?
    let hasChildren: Bool
    let iconSize: Font
    let circleSize: CGFloat
    let minHeight: CGFloat
    let onSelect: (CGRect?) -> Void
    let onOpenChildren: (CGRect?) -> Void

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
        Button {
            if hasChildren {
                onOpenChildren(globalFrame)
            } else {
                onSelect(globalFrame)
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(color.opacity(isSelected ? 0.18 : 0.10))
                        .frame(width: circleSize, height: circleSize)

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
                        .font(DesignSystem.Typography.supportingLabel)
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
        .buttonStyle(CategorySelectionTileButtonStyle(color: color))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasChildren ? "\(rootName)，包含小类" : rootName)
        .accessibilityValue(
            isSelected
                ? "已选中：\(selectedCategory?.entryDisplayName ?? rootName)"
                : "未选中"
        )
        .accessibilityHint(hasChildren ? "点按打开分类圆盘" : "")
        .accessibilityAddTraits(.isButton)
    }
}

private struct CategorySelectionTileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(configuration.isPressed ? 0.09 : 0))
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
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
    @State private var dialState = CategoryWheelDialState()
    @State private var selectionPulseIndex: Int?
    @State private var transitionTask: Task<Void, Never>?

    private enum PresentationPhase: Equatable {
        case hidden
        case open
        case selecting(Int)
        case closing

        var acceptsInput: Bool {
            self == .open
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
                    .opacity(isPresented ? (colorScheme == .dark ? 0.45 : 0.30) : 0)
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
            .accessibilityIdentifier("categoryWheelOverlay")
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
                activeIndex: dialState.activeIndex ?? selectionPulseIndex
            )

            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                categoryLabel(child, index: index, layout: layout)
            }

            centerHub(size: wheelSize)
        }
        .frame(width: wheelSize, height: wheelSize)
        .contentShape(Circle())
        .simultaneousGesture(dialGesture(layout: layout))
        .scaleEffect(isPresented || reduceMotion ? 1 : 0.92)
        .offset(
            x: isPresented || reduceMotion ? 0 : sourceOffset.width * 0.24,
            y: isPresented || reduceMotion ? 0 : sourceOffset.height * 0.24
        )
        .opacity(isPresented ? 1 : 0)
        .allowsHitTesting(phase.acceptsInput)
    }

    private func categoryLabel(_ child: Category, index: Int, layout: CategoryWheelLayout) -> some View {
        let isActive = dialState.activeIndex == index || selectionPulseIndex == index
        let isSelected = selectedCategory?.id == child.id
        let childColor = Color(hex: child.colorHex)
        let point = layout.labelPoint(for: index, radialOffset: isActive ? -2 : 0)

        return VStack(spacing: 4) {
            Image(systemName: child.icon)
                .font(DesignSystem.Typography.wheelIcon)
                .symbolRenderingMode(.monochrome)
                .scaleEffect(selectionPulseIndex == index ? 1.10 : isActive ? 1.06 : 1)
            Text(child.name)
                .font(DesignSystem.Typography.wheelLabel)
                .fontWidth(layout.itemCount >= 8 ? .condensed : .standard)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .lineSpacing(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: layout.labelSize.width)
        }
        .foregroundStyle(isActive || isSelected ? childColor : DesignSystem.textPrimary)
        .frame(width: layout.labelSize.width, height: layout.labelSize.height)
        .position(point)
        .opacity(labelsVisible ? (dialState.activeIndex == nil || isActive ? 1 : 0.68) : 0)
        .offset(y: labelsVisible ? 0 : 7)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: labelsVisible
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.11), value: isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(child.name)，\(parentName)")
        .accessibilityIdentifier("categoryWheelChild-\(child.name)")
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
            HapticManager.categoryWheelConfirmed()
            selectionPulseIndex = nil
            phase = .selecting(-1)
            scheduleSelection {
                onSelectParent()
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: parentIcon)
                    .font(.title3.weight(.semibold))
                Text(parentName)
                    .font(DesignSystem.Typography.wheelHubTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("使用大类")
                    .font(DesignSystem.Typography.supportingLabel)
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
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(CategoryWheelPalette.edgeLine, lineWidth: 1)
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
                    .font(DesignSystem.Typography.controlLabel)
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
                switch dialState.update(location: value.location, layout: layout) {
                case .entered, .moved:
                    HapticManager.categoryWheelSectorChanged()
                case .unchanged, .exited:
                    break
                }
            }
            .onEnded { value in
                guard phase.acceptsInput else { return }
                let index = layout.index(at: value.location)
                dialState.reset()
                guard let index, children.indices.contains(index) else { return }
                confirmChild(at: index)
            }
    }

    private func confirmChild(at index: Int) {
        guard phase.acceptsInput, children.indices.contains(index) else { return }
        phase = .selecting(index)
        selectionPulseIndex = index
        HapticManager.categoryWheelConfirmed()
        scheduleSelection {
            onSelectChild(children[index])
        }
    }

    private func present() {
        transitionTask?.cancel()
        phase = .open
        HapticManager.prepareCategoryWheel()
        HapticManager.categoryWheelOpened()

        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
            isPresented = true
        }

        labelsVisible = true
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
        dialState.reset()
        labelsVisible = false

        withAnimation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .easeOut(duration: 0.16)
        ) {
            isPresented = false
        }

        transitionTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: reduceMotion ? 120_000_000 : 160_000_000)
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

    @ViewBuilder
    var body: some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            decorations
                .liquidGlassSurface(shape: .circle)
        } else {
            legacySurface
        }
#else
        legacySurface
#endif
    }

    /// iOS 17/18 没有系统 Liquid Glass：系统材质做基底，手绘折射高光沿近似玻璃厚度。
    private var legacySurface: some View {
        decorations
            .background {
                Circle()
                    .fill(.thinMaterial)
                    .shadow(
                        color: .black.opacity(colorScheme == .dark ? 0.38 : 0.18),
                        radius: 24,
                        x: 0,
                        y: 14
                    )
            }
            .overlay(legacySpecularRim)
    }

    /// 左上主高光、右下弱反光的边缘，光感随圆周变化而非均匀描边。
    private var legacySpecularRim: some View {
        ZStack {
            Circle()
                .strokeBorder(CategoryWheelPalette.edgeLine, lineWidth: 1)
            Circle()
                .inset(by: 1.1)
                .strokeBorder(
                    AngularGradient(
                        stops: [
                            .init(color: CategoryWheelPalette.specularStrong, location: 0),
                            .init(color: CategoryWheelPalette.specularSoft, location: 0.18),
                            .init(color: .clear, location: 0.38),
                            .init(color: CategoryWheelPalette.specularSoft, location: 0.52),
                            .init(color: .clear, location: 0.66),
                            .init(color: CategoryWheelPalette.specularSoft, location: 0.84),
                            .init(color: CategoryWheelPalette.specularStrong, location: 1)
                        ],
                        center: .center,
                        angle: .degrees(-135)
                    ),
                    lineWidth: 1.3
                )
        }
        .allowsHitTesting(false)
    }

    /// 扇区色彩与中心透镜。基底透明，玻璃层在下方（系统 glassEffect 或 legacy 材质）。
    private var decorations: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            let innerRect = circleRect(radius: layout.innerRadius)

            for (index, child) in children.enumerated() {
                let isActive = activeIndex == index
                let isSelected = selectedCategoryID == child.id
                let color = Color(hex: child.colorHex)
                let radialOffset: CGFloat = isActive ? 2.5 : 0
                let path = layout.sectorPath(for: index, radialOffset: radialOffset)
                let outerStop = layout.labelPoint(for: index, radialOffset: layout.labelRadius * 0.55)
                let innerStop = layout.labelPoint(for: index, radialOffset: -layout.labelRadius * 0.10)

                if isActive {
                    var glow = context
                    glow.addFilter(.shadow(color: color.opacity(0.45), radius: 9))
                    glow.fill(path, with: .color(color.opacity(colorScheme == .dark ? 0.30 : 0.20)))
                }

                // 色彩只在外沿聚拢，中部留给中性玻璃；暗色再叠 screen 混合避免发闷。
                var wedge = context
                if colorScheme == .dark {
                    wedge.blendMode = .screen
                }
                wedge.fill(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [
                            color.opacity(tintPeak(isActive: isActive, isSelected: isSelected)),
                            color.opacity(0)
                        ]),
                        startPoint: outerStop,
                        endPoint: innerStop
                    )
                )

                // 外沿一道彩色光弧：光从玻璃边缘透入的痕迹，也是各分区的色彩锚点。
                let middle = layout.middleAngle(for: index)
                let middleRadians = Angle.degrees(middle).radians
                let arcCenter = CGPoint(
                    x: layout.center.x + CGFloat(cos(middleRadians)) * radialOffset,
                    y: layout.center.y + CGFloat(sin(middleRadians)) * radialOffset
                )
                let arcInset = layout.sectorInset + 1.2
                var rimArc = Path()
                rimArc.addArc(
                    center: arcCenter,
                    radius: layout.outerRadius - 0.8,
                    startAngle: .degrees(middle - layout.sectorAngle / 2 + arcInset),
                    endAngle: .degrees(middle + layout.sectorAngle / 2 - arcInset),
                    clockwise: false
                )
                context.stroke(
                    rimArc,
                    with: .color(color.opacity(rimArcOpacity(isActive: isActive, isSelected: isSelected))),
                    lineWidth: isActive ? 2 : 1.6
                )

                if isActive || isSelected {
                    context.stroke(
                        path,
                        with: .color(color.opacity(isActive ? 0.50 : 0.30)),
                        lineWidth: isActive ? 1.1 : 0.8
                    )
                }
            }

            var groove = context
            groove.addFilter(.blur(radius: 1.8))
            groove.stroke(
                Path(ellipseIn: innerRect.insetBy(dx: -1.4, dy: -1.4)),
                with: .color(CategoryWheelPalette.groove),
                lineWidth: 2.6
            )

            context.fill(
                Path(ellipseIn: innerRect),
                with: .radialGradient(
                    Gradient(colors: [CategoryWheelPalette.hubSheen, CategoryWheelPalette.hubSheenFade]),
                    center: CGPoint(
                        x: innerRect.midX - innerRect.width * 0.14,
                        y: innerRect.midY - innerRect.height * 0.16
                    ),
                    startRadius: 0,
                    endRadius: layout.innerRadius * 1.15
                )
            )
            context.stroke(
                Path(ellipseIn: innerRect),
                with: .color(CategoryWheelPalette.hubHairline),
                lineWidth: 1
            )
        }
        .frame(width: layout.size, height: layout.size)
    }

    /// 色彩从外沿最浓、向圆心渐隐至无，像光从玻璃边缘透入。暗色档位按 screen 混合调校。
    private func tintPeak(isActive: Bool, isSelected: Bool) -> Double {
        let dark = colorScheme == .dark
        if isActive { return dark ? 0.52 : 0.38 }
        if isSelected { return dark ? 0.38 : 0.28 }
        return dark ? 0.30 : 0.20
    }

    private func rimArcOpacity(isActive: Bool, isSelected: Bool) -> Double {
        let dark = colorScheme == .dark
        if isActive { return dark ? 0.85 : 0.70 }
        if isSelected { return dark ? 0.65 : 0.55 }
        return dark ? 0.50 : 0.40
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
    static let specularStrong = Color(uiColor: UIColor { traits in
        UIColor.white.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.30 : 0.85)
    })

    static let specularSoft = Color(uiColor: UIColor { traits in
        UIColor.white.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.10 : 0.35)
    })

    static let edgeLine = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.14)
            : UIColor.black.withAlphaComponent(0.10)
    })

    static let groove = Color(uiColor: UIColor { traits in
        UIColor.black.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.24 : 0.10)
    })

    static let hubSheen = Color(uiColor: UIColor { traits in
        UIColor.white.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.10 : 0.42)
    })

    static let hubSheenFade = Color(uiColor: UIColor { traits in
        UIColor.white.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.015 : 0.05)
    })

    static let hubHairline = Color(uiColor: UIColor { traits in
        UIColor.white.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.22 : 0.70)
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
