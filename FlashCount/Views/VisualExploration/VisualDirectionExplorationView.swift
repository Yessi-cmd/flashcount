#if DEBUG
import SwiftUI

/// Three isolated visual treatments for the same budget content.
/// This lab deliberately uses fixed sample data and never writes to SwiftData.
enum VisualDirection: String, CaseIterable, Identifiable {
    case restrained = "A"
    case soft = "B"
    case precise = "C"

    var id: Self { self }

    var name: String {
        switch self {
        case .restrained: return "极度克制"
        case .soft: return "柔和但不幼稚"
        case .precise: return "精密工具感"
        }
    }
}

struct VisualDirectionExplorationView: View {
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
                RestrainedBudgetDirection(
                    primaryAction: { actionMessage = "已打开“调整预算”演示入口；不会修改真实预算。" },
                    secondaryAction: { actionMessage = "已打开“查看明细”演示入口；不会读取真实账目。" }
                )
            case .soft:
                SoftBudgetDirection(
                    primaryAction: { actionMessage = "已打开“调整预算”演示入口；不会修改真实预算。" },
                    secondaryAction: { actionMessage = "已打开“查看明细”演示入口；不会读取真实账目。" }
                )
            case .precise:
                PreciseBudgetDirection(
                    primaryAction: { actionMessage = "已打开“调整预算”演示入口；不会修改真实预算。" },
                    secondaryAction: { actionMessage = "已打开“查看明细”演示入口；不会读取真实账目。" }
                )
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
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

    private var directionSwitcher: some View {
        VStack(spacing: 10) {
            HStack {
                Text("视觉方向探索")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hex: "#626866"))
                Spacer()
                Text("方向 \(selectedDirection.rawValue) · \(selectedDirection.name)")
                    .font(.caption2)
                    .foregroundStyle(Color(hex: "#858B88"))
            }

            HStack(spacing: 6) {
                ForEach(VisualDirection.allCases) { direction in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            selectedDirection = direction
                        }
                    } label: {
                        Text(direction.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundStyle(selectedDirection == direction ? .white : Color(hex: "#626866"))
                            .background(selectedDirection == direction ? Color(hex: "#42675D") : Color(hex: "#F0F2EF"))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(ExplorationPressStyle())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.white)
        .overlay(alignment: .top) {
            Rectangle().fill(Color(hex: "#E3E6E2")).frame(height: 1)
        }
    }
}

private enum ExplorationContent {
    static let title = "本期预算"
    static let period = "7月 1日 — 7月 31日"
    static let status = "节奏正常"
    static let remaining = "¥3,280"
    static let budget = "¥8,000"
    static let spent = "¥4,720"
    static let usage = "59%"
    static let todayAllowance = "¥168"
    static let daysRemaining = "20 天"
    static let projectedBalance = "¥860"
    static let statusMessage = "按当前速度，周期结束时预计结余 ¥860"

    static let transactions: [ExplorationTransaction] = [
        .init(icon: "fork.knife", title: "午餐", detail: "餐饮 · 今天 12:26", amount: "−¥42"),
        .init(icon: "tram.fill", title: "地铁", detail: "交通 · 今天 08:42", amount: "−¥18"),
        .init(icon: "basket.fill", title: "日用品", detail: "购物 · 昨天 19:10", amount: "−¥126")
    ]
}

private struct ExplorationTransaction: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
    let amount: String
}

private struct ExplorationPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Direction A: restrained

private struct RestrainedBudgetDirection: View {
    let primaryAction: () -> Void
    let secondaryAction: () -> Void
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
                    status
                    recentTransactions
                    actions
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ExplorationContent.title)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(ink)
            Text(ExplorationContent.period)
                .font(.subheadline)
                .foregroundStyle(secondary)
        }
        .padding(.bottom, 34)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("本期剩余")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(secondary)
                Spacer()
                Label(ExplorationContent.status, systemImage: "circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(accent)
                    .labelStyle(CompactStatusLabelStyle())
            }

            Text(ExplorationContent.remaining)
                .font(.system(size: 43, weight: .medium, design: .default).monospacedDigit())
                .tracking(-1.2)
                .foregroundStyle(ink)
                .padding(.top, 10)

            HStack(spacing: 5) {
                Text("预算 \(ExplorationContent.budget)")
                Text("·")
                Text("已用 \(ExplorationContent.spent)（\(ExplorationContent.usage)）")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(secondary)
            .padding(.top, 7)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(line).frame(height: 3)
                    Rectangle().fill(accent).frame(width: proxy.size.width * 0.59, height: 3)
                }
            }
            .frame(height: 3)
            .padding(.top, 22)

            HStack(spacing: 0) {
                restrainedMetric("今日可花", ExplorationContent.todayAllowance)
                restrainedMetric("剩余天数", ExplorationContent.daysRemaining)
                restrainedMetric("预计结余", ExplorationContent.projectedBalance)
            }
            .padding(.top, 23)
        }
        .padding(.bottom, 28)
        .overlay(alignment: .bottom) { Rectangle().fill(line).frame(height: 1) }
    }

    private func restrainedMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(tertiary)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var status: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(accent)
                .padding(.top, 2)
            Text(ExplorationContent.statusMessage)
                .font(.subheadline)
                .foregroundStyle(secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 19)
        .overlay(alignment: .bottom) { Rectangle().fill(line).frame(height: 1) }
    }

    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("最近支出").font(.headline.weight(.semibold)).foregroundStyle(ink)
                Spacer()
                Text("查看全部").font(.caption).foregroundStyle(secondary)
            }
            .padding(.top, 27)
            .padding(.bottom, 9)

            ForEach(ExplorationContent.transactions) { transaction in
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

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: secondaryAction) {
                Text("查看明细")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(ink)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(line, lineWidth: 1))
            }
            Button(action: primaryAction) {
                Text("调整预算")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(.white)
                    .background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
        .buttonStyle(ExplorationPressStyle())
        .padding(.top, 24)
    }
}

private struct CompactStatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 6))
            configuration.title
        }
    }
}

// MARK: - Direction B: soft

private struct SoftBudgetDirection: View {
    let primaryAction: () -> Void
    let secondaryAction: () -> Void
    private let ink = Color(hex: "#26312D")
    private let secondary = Color(hex: "#64706A")
    private let tertiary = Color(hex: "#89928E")
    private let accent = Color(hex: "#4E766A")
    private let surface = Color(hex: "#FFFFFF")
    private let softSurface = Color(hex: "#E8F0EC")
    private let line = Color(hex: "#DFE5E1")

    var body: some View {
        ZStack {
            Color(hex: "#F3F1EC").ignoresSafeArea()
            VStack(spacing: 0) {
                Color(hex: "#E5ECE7").frame(height: 112)
                Spacer()
            }
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    summaryCard
                    statusCard
                    recentCard
                    actions
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(ExplorationContent.title)
                .font(.system(size: 29, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
            Text(ExplorationContent.period)
                .font(.subheadline)
                .foregroundStyle(secondary)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("本期剩余").font(.subheadline.weight(.medium)).foregroundStyle(secondary)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(accent).frame(width: 7, height: 7)
                    Text(ExplorationContent.status).font(.caption.weight(.semibold))
                }
                .foregroundStyle(accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(softSurface)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(ExplorationContent.remaining)
                    .font(.system(size: 42, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(ink)
                Text("预算 \(ExplorationContent.budget) · 已用 \(ExplorationContent.spent)（\(ExplorationContent.usage)）")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(secondary)
            }

            VStack(spacing: 8) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#E3E7E3"))
                        RoundedRectangle(cornerRadius: 4).fill(accent).frame(width: proxy.size.width * 0.59)
                    }
                }
                .frame(height: 8)

                HStack(spacing: 8) {
                    softMetric("今日可花", ExplorationContent.todayAllowance)
                    softMetric("剩余天数", ExplorationContent.daysRemaining)
                    softMetric("预计结余", ExplorationContent.projectedBalance)
                }
            }
        }
        .padding(20)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(line.opacity(0.8), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.035), radius: 12, y: 5)
    }

    private func softMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(tertiary)
            Text(value).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color(hex: "#F3F6F3"))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(accent)
            Text(ExplorationContent.statusMessage)
                .font(.subheadline)
                .foregroundStyle(ink)
            Spacer(minLength: 0)
        }
        .padding(15)
        .background(softSurface.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("最近支出").font(.headline.weight(.semibold)).foregroundStyle(ink)
                Spacer()
                Text("查看全部").font(.caption.weight(.medium)).foregroundStyle(accent)
            }
            .padding(.bottom, 9)

            ForEach(ExplorationContent.transactions) { transaction in
                HStack(spacing: 12) {
                    Image(systemName: transaction.icon)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(accent)
                        .frame(width: 34, height: 34)
                        .background(softSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(line.opacity(0.8), lineWidth: 1))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: secondaryAction) {
                Text("查看明细")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(accent)
                    .background(softSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            Button(action: primaryAction) {
                Text("调整预算")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(.white)
                    .background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        }
        .buttonStyle(ExplorationPressStyle())
    }
}

// MARK: - Direction C: precise

private struct PreciseBudgetDirection: View {
    let primaryAction: () -> Void
    let secondaryAction: () -> Void
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
                    statusPanel
                    recentPanel
                    actions
                }
                .padding(.horizontal, 18)
                .padding(.top, 17)
                .padding(.bottom, 22)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text(ExplorationContent.title)
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(ink)
                Text(ExplorationContent.period.uppercased())
                    .font(.caption.monospaced())
                    .foregroundStyle(tertiary)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 6, height: 6)
                Text(ExplorationContent.status)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(surface)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(line, lineWidth: 1))
        }
        .padding(.bottom, 4)
    }

    private var summaryPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 13) {
                Rectangle().fill(accent).frame(width: 3, height: 57)
                VStack(alignment: .leading, spacing: 5) {
                    Text("本期剩余")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondary)
                        .textCase(.uppercase)
                    Text(ExplorationContent.remaining)
                        .font(.system(size: 38, weight: .semibold, design: .monospaced))
                        .tracking(-1.5)
                        .foregroundStyle(ink)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text("使用率").font(.caption2).foregroundStyle(tertiary)
                    Text(ExplorationContent.usage)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(accent)
                }
            }

            HStack(spacing: 4) {
                ForEach(0..<10, id: \.self) { index in
                    Rectangle()
                        .fill(index < 6 ? accent : Color(hex: "#DFE4E6"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 5)
                }
            }

            HStack {
                Text("预算 \(ExplorationContent.budget)")
                Spacer()
                Text("已用 \(ExplorationContent.spent)")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(secondary)

            HStack(spacing: 0) {
                preciseMetric("今日可花", ExplorationContent.todayAllowance)
                divider
                preciseMetric("剩余天数", ExplorationContent.daysRemaining)
                divider
                preciseMetric("预计结余", ExplorationContent.projectedBalance)
            }
            .padding(.vertical, 12)
            .background(Color(hex: "#F2F5F6"))
            .overlay(Rectangle().stroke(line.opacity(0.8), lineWidth: 1))
        }
        .padding(17)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var divider: some View {
        Rectangle().fill(line).frame(width: 1, height: 34)
    }

    private func preciseMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(tertiary)
            Text(value).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private var statusPanel: some View {
        HStack(spacing: 11) {
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 23, height: 23)
                .background(accent)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text("预测状态").font(.caption2.weight(.semibold)).foregroundStyle(tertiary)
                Text(ExplorationContent.statusMessage).font(.subheadline).foregroundStyle(ink)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(line, lineWidth: 1))
    }

    private var recentPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("最近支出").font(.subheadline.weight(.semibold)).foregroundStyle(ink)
                Spacer()
                Text("查看全部  →").font(.caption.monospaced()).foregroundStyle(accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(hex: "#E8EDEF"))

            ForEach(Array(ExplorationContent.transactions.enumerated()), id: \.element.id) { index, transaction in
                HStack(spacing: 11) {
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
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(line).frame(height: 1) }
            }
        }
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var actions: some View {
        HStack(spacing: 9) {
            Button(action: secondaryAction) {
                Text("查看明细")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(ink)
                    .background(surface)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(line, lineWidth: 1))
            }
            Button(action: primaryAction) {
                HStack(spacing: 7) {
                    Image(systemName: "slider.horizontal.3").font(.caption.weight(.bold))
                    Text("调整预算")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(.white)
                .background(accent)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .buttonStyle(ExplorationPressStyle())
    }
}
#endif
