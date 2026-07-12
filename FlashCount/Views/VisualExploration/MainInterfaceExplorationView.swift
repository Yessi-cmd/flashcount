import SwiftUI

/// Isolated main-interface visual lab. It uses fixed content and does not touch SwiftData.
struct MainInterfaceExplorationView: View {
    @State private var selectedDirection: VisualDirection
    @State private var actionMessage: String?
    let allowsDirectionSwitching: Bool

    init(initialDirection: VisualDirection = .restrained, allowsDirectionSwitching: Bool = true) {
        _selectedDirection = State(initialValue: initialDirection)
        self.allowsDirectionSwitching = allowsDirectionSwitching
    }

    var body: some View {
        Group {
            switch selectedDirection {
            case .restrained:
                RestrainedMainInterface(action: showDemoAction)
            case .soft:
                SoftMainInterface(action: showDemoAction)
            case .precise:
                PreciseMainInterface(action: showDemoAction)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if allowsDirectionSwitching {
                directionSwitcher
            }
        }
        .alert("视觉演示", isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { actionMessage = nil }
        } message: {
            Text(actionMessage ?? "")
        }
    }

    private func showDemoAction(_ title: String) {
        actionMessage = "已触发“\(title)”演示；不会读取或写入真实数据。"
    }

    private var directionSwitcher: some View {
        HStack(spacing: 8) {
            Text("主界面方向")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(hex: "#626866"))
            Spacer()
            ForEach(VisualDirection.allCases) { direction in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selectedDirection = direction
                    }
                } label: {
                    Text(direction.rawValue)
                        .font(.caption.weight(.semibold))
                        .frame(width: 34, height: 28)
                        .foregroundStyle(selectedDirection == direction ? .white : Color(hex: "#626866"))
                        .background(selectedDirection == direction ? Color(hex: "#42675D") : Color(hex: "#EEF0ED"))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(HomePressStyle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(hex: "#E3E6E2")).frame(height: 1)
        }
    }
}

private enum MainExplorationContent {
    static let title = "生活账本"
    static let date = "7月11日 · 周六"
    static let expense = "¥4,720"
    static let change = "较上月减少 8%"
    static let income = "¥12,800"
    static let balance = "¥8,080"
    static let budgetUsage = "59%"
    static let budgetRemaining = "¥3,280"

    static let transactions: [MainExplorationTransaction] = [
        .init(icon: "fork.knife", title: "午餐", detail: "餐饮 · 今天 12:26", amount: "−¥42"),
        .init(icon: "tram.fill", title: "地铁", detail: "交通 · 今天 08:42", amount: "−¥18"),
        .init(icon: "basket.fill", title: "日用品", detail: "购物 · 昨天 19:10", amount: "−¥126")
    ]
}

private struct MainExplorationTransaction: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
    let amount: String
}

private struct HomePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Direction A

private struct RestrainedMainInterface: View {
    let action: (String) -> Void
    private let ink = Color(hex: "#202523")
    private let secondary = Color(hex: "#68706C")
    private let tertiary = Color(hex: "#929894")
    private let line = Color(hex: "#DADDD9")
    private let accent = Color(hex: "#315F55")

    var body: some View {
        ZStack {
            Color(hex: "#F8F8F6").ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    summary
                    budgetState
                    transactions
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 22)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(MainExplorationContent.title)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(ink)
                Text(MainExplorationContent.date)
                    .font(.subheadline)
                    .foregroundStyle(secondary)
            }
            Spacer()
            HStack(spacing: 16) {
                iconButton("magnifyingglass", title: "搜索")
                iconButton("line.3.horizontal.decrease", title: "筛选")
            }
            .padding(.top, 8)
        }
        .padding(.bottom, 31)
    }

    private func iconButton(_ icon: String, title: String) -> some View {
        Button { action(title) } label: {
            Image(systemName: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(secondary)
                .frame(width: 24, height: 28)
        }
        .buttonStyle(HomePressStyle())
        .accessibilityLabel(title)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("本月支出").font(.subheadline.weight(.medium)).foregroundStyle(secondary)
                Spacer()
                Label(MainExplorationContent.change, systemImage: "arrow.down.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(accent)
            }

            Text(MainExplorationContent.expense)
                .font(.system(size: 43, weight: .medium).monospacedDigit())
                .tracking(-1.2)
                .foregroundStyle(ink)
                .padding(.top, 9)

            HStack(spacing: 0) {
                plainMetric("本月收入", MainExplorationContent.income)
                plainMetric("本月结余", MainExplorationContent.balance)
            }
            .padding(.top, 19)
        }
        .padding(.bottom, 24)
        .overlay(alignment: .bottom) { Rectangle().fill(line).frame(height: 1) }
    }

    private func plainMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(tertiary)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var budgetState: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("本期预算").font(.subheadline.weight(.medium)).foregroundStyle(ink)
                Spacer()
                Text("已用 \(MainExplorationContent.budgetUsage) · 剩余 \(MainExplorationContent.budgetRemaining)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(line).frame(height: 3)
                    Rectangle().fill(accent).frame(width: proxy.size.width * 0.59, height: 3)
                }
            }
            .frame(height: 3)
        }
        .padding(.vertical, 19)
        .overlay(alignment: .bottom) { Rectangle().fill(line).frame(height: 1) }
    }

    private var transactions: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("最近记录").font(.headline.weight(.semibold)).foregroundStyle(ink)
                Spacer()
                Button("查看全部") { action("查看全部") }
                    .font(.caption)
                    .foregroundStyle(secondary)
            }
            .padding(.top, 25)
            .padding(.bottom, 8)

            ForEach(MainExplorationContent.transactions) { transaction in
                HStack(spacing: 13) {
                    Image(systemName: transaction.icon)
                        .font(.subheadline)
                        .foregroundStyle(secondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(transaction.title).font(.subheadline.weight(.medium)).foregroundStyle(ink)
                        Text(transaction.detail).font(.caption).foregroundStyle(tertiary)
                    }
                    Spacer()
                    Text(transaction.amount).font(.subheadline.monospacedDigit()).foregroundStyle(ink)
                }
                .padding(.vertical, 13)
                .overlay(alignment: .bottom) { Rectangle().fill(line.opacity(0.8)).frame(height: 1) }
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            restrainedTab("book.fill", "账本", selected: true)
            restrainedTab("chart.pie", "预算")
            Button { action("记一笔") } label: {
                VStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 43, height: 35)
                        .background(accent)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    Text("记一笔").font(.caption2.weight(.medium)).foregroundStyle(accent)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(HomePressStyle())
            restrainedTab("chart.bar", "报表")
            restrainedTab("building.columns", "资产")
        }
        .padding(.horizontal, 8)
        .padding(.top, 9)
        .padding(.bottom, 5)
        .background(Color(hex: "#F8F8F6"))
        .overlay(alignment: .top) { Rectangle().fill(line).frame(height: 1) }
    }

    private func restrainedTab(_ icon: String, _ title: String, selected: Bool = false) -> some View {
        Button { action(title) } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.subheadline.weight(selected ? .semibold : .regular))
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(selected ? accent : tertiary)
        }
        .buttonStyle(HomePressStyle())
    }
}

// MARK: - Direction B

private struct SoftMainInterface: View {
    let action: (String) -> Void
    private let ink = Color(hex: "#26312D")
    private let secondary = Color(hex: "#64706A")
    private let tertiary = Color(hex: "#89928E")
    private let accent = Color(hex: "#4E766A")
    private let surface = Color.white
    private let softSurface = Color(hex: "#E8F0EC")
    private let line = Color(hex: "#DFE5E1")

    var body: some View {
        ZStack {
            Color(hex: "#F3F1EC").ignoresSafeArea()
            VStack(spacing: 0) {
                Color(hex: "#E5ECE7").frame(height: 168)
                Spacer()
            }
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    summaryCard
                    budgetState
                    transactionsCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(MainExplorationContent.title)
                    .font(.system(size: 29, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                Text(MainExplorationContent.date).font(.subheadline).foregroundStyle(secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                softIconButton("magnifyingglass", "搜索")
                softIconButton("line.3.horizontal.decrease", "筛选")
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 3)
    }

    private func softIconButton(_ icon: String, _ title: String) -> some View {
        Button { action(title) } label: {
            Image(systemName: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(accent)
                .frame(width: 36, height: 36)
                .background(surface.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(HomePressStyle())
        .accessibilityLabel(title)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text("本月支出").font(.subheadline.weight(.medium)).foregroundStyle(secondary)
                Spacer()
                Label(MainExplorationContent.change, systemImage: "arrow.down.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(softSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            Text(MainExplorationContent.expense)
                .font(.system(size: 42, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(ink)
            HStack(spacing: 9) {
                softMetric("本月收入", MainExplorationContent.income)
                softMetric("本月结余", MainExplorationContent.balance)
            }
        }
        .padding(20)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(line.opacity(0.8), lineWidth: 1))
        .shadow(color: .black.opacity(0.035), radius: 12, y: 5)
    }

    private func softMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(tertiary)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(hex: "#F3F6F3"))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var budgetState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("本期预算", systemImage: "chart.pie.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                Spacer()
                Text("已用 \(MainExplorationContent.budgetUsage)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(accent)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#DCE4DF"))
                    RoundedRectangle(cornerRadius: 4).fill(accent).frame(width: proxy.size.width * 0.59)
                }
            }
            .frame(height: 7)
            Text("剩余 \(MainExplorationContent.budgetRemaining)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(secondary)
        }
        .padding(15)
        .background(softSurface.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private var transactionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("最近记录").font(.headline.weight(.semibold)).foregroundStyle(ink)
                Spacer()
                Button("查看全部") { action("查看全部") }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(accent)
            }
            .padding(.bottom, 8)

            ForEach(MainExplorationContent.transactions) { transaction in
                HStack(spacing: 12) {
                    Image(systemName: transaction.icon)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(accent)
                        .frame(width: 34, height: 34)
                        .background(softSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(transaction.title).font(.subheadline.weight(.medium)).foregroundStyle(ink)
                        Text(transaction.detail).font(.caption).foregroundStyle(tertiary)
                    }
                    Spacer()
                    Text(transaction.amount).font(.subheadline.weight(.medium).monospacedDigit()).foregroundStyle(ink)
                }
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(line).frame(height: 1) }
            }
        }
        .padding(17)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(line.opacity(0.8), lineWidth: 1))
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            softTab("book.fill", "账本", selected: true)
            softTab("chart.pie", "预算")
            Button { action("记一笔") } label: {
                VStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 42)
                        .background(accent)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                        .shadow(color: accent.opacity(0.20), radius: 8, y: 3)
                    Text("记一笔").font(.caption2.weight(.medium)).foregroundStyle(accent)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(HomePressStyle())
            softTab("chart.bar", "报表")
            softTab("building.columns", "资产")
        }
        .padding(.horizontal, 7)
        .padding(.top, 9)
        .padding(.bottom, 5)
        .background(surface)
        .overlay(alignment: .top) { Rectangle().fill(line).frame(height: 1) }
        .shadow(color: .black.opacity(0.05), radius: 12, y: -4)
    }

    private func softTab(_ icon: String, _ title: String, selected: Bool = false) -> some View {
        Button { action(title) } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.subheadline.weight(selected ? .semibold : .regular))
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(selected ? accent : tertiary)
        }
        .buttonStyle(HomePressStyle())
    }
}

// MARK: - Direction C

private struct PreciseMainInterface: View {
    let action: (String) -> Void
    private let ink = Color(hex: "#1E292E")
    private let secondary = Color(hex: "#56656C")
    private let tertiary = Color(hex: "#819097")
    private let accent = Color(hex: "#315F73")
    private let line = Color(hex: "#CCD4D7")
    private let surface = Color(hex: "#FAFBFB")

    var body: some View {
        ZStack {
            Color(hex: "#F0F3F4").ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    summaryPanel
                    budgetPanel
                    transactionsPanel
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(MainExplorationContent.title)
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(ink)
                Text(MainExplorationContent.date.uppercased())
                    .font(.caption.monospaced())
                    .foregroundStyle(tertiary)
            }
            Spacer()
            HStack(spacing: 7) {
                preciseIconButton("magnifyingglass", "搜索")
                preciseIconButton("line.3.horizontal.decrease", "筛选")
            }
        }
        .padding(.bottom, 3)
    }

    private func preciseIconButton(_ icon: String, _ title: String) -> some View {
        Button { action(title) } label: {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 32)
                .background(surface)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(line, lineWidth: 1))
        }
        .buttonStyle(HomePressStyle())
        .accessibilityLabel(title)
    }

    private var summaryPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("本月支出").font(.caption.weight(.semibold)).foregroundStyle(secondary)
                    Text(MainExplorationContent.expense)
                        .font(.system(size: 38, weight: .semibold, design: .monospaced))
                        .tracking(-1.4)
                        .foregroundStyle(ink)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("环比").font(.caption2).foregroundStyle(tertiary)
                    Label("−8%", systemImage: "arrow.down.right")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(accent)
                }
            }
            HStack(spacing: 0) {
                preciseMetric("本月收入", MainExplorationContent.income)
                Rectangle().fill(line).frame(width: 1, height: 33)
                preciseMetric("本月结余", MainExplorationContent.balance)
            }
            .padding(.vertical, 11)
            .background(Color(hex: "#F2F5F6"))
            .overlay(Rectangle().stroke(line.opacity(0.8), lineWidth: 1))
            Text(MainExplorationContent.change)
                .font(.caption)
                .foregroundStyle(secondary)
        }
        .padding(17)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func preciseMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(tertiary)
            Text(value).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
    }

    private var budgetPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("本期预算").font(.subheadline.weight(.semibold)).foregroundStyle(ink)
                Spacer()
                Text("\(MainExplorationContent.budgetUsage) / 剩余 \(MainExplorationContent.budgetRemaining)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(accent)
            }
            HStack(spacing: 4) {
                ForEach(0..<10, id: \.self) { index in
                    Rectangle()
                        .fill(index < 6 ? accent : Color(hex: "#DFE4E6"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 5)
                }
            }
        }
        .padding(14)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(line, lineWidth: 1))
    }

    private var transactionsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("最近记录").font(.subheadline.weight(.semibold)).foregroundStyle(ink)
                Spacer()
                Button("查看全部  →") { action("查看全部") }
                    .font(.caption.monospaced())
                    .foregroundStyle(accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color(hex: "#E8EDEF"))

            ForEach(Array(MainExplorationContent.transactions.enumerated()), id: \.element.id) { index, transaction in
                HStack(spacing: 10) {
                    Text(String(format: "%02d", index + 1))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(tertiary)
                    Image(systemName: transaction.icon)
                        .font(.caption)
                        .foregroundStyle(accent)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(transaction.title).font(.subheadline.weight(.medium)).foregroundStyle(ink)
                        Text(transaction.detail).font(.caption2).foregroundStyle(tertiary)
                    }
                    Spacer()
                    Text(transaction.amount).font(.subheadline.weight(.medium).monospacedDigit()).foregroundStyle(ink)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .overlay(alignment: .bottom) { Rectangle().fill(line).frame(height: 1) }
            }
        }
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            preciseTab("book.fill", "账本", selected: true)
            preciseTab("chart.pie", "预算")
            Button { action("记一笔") } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.caption.weight(.bold))
                    Text("记一笔").font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(height: 36)
                .padding(.horizontal, 8)
                .background(accent)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(HomePressStyle())
            preciseTab("chart.bar", "报表")
            preciseTab("building.columns", "资产")
        }
        .padding(.horizontal, 7)
        .padding(.top, 8)
        .padding(.bottom, 5)
        .background(surface)
        .overlay(alignment: .top) { Rectangle().fill(line).frame(height: 1) }
    }

    private func preciseTab(_ icon: String, _ title: String, selected: Bool = false) -> some View {
        Button { action(title) } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.caption.weight(selected ? .semibold : .regular))
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(selected ? accent : tertiary)
        }
        .buttonStyle(HomePressStyle())
    }
}
