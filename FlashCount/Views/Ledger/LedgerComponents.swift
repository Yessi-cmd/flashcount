import SwiftUI

/// 账本的时间范围筛选。`payCycle` 跟着设置里的发薪日走，`custom` 使用用户自选区间。
enum LedgerPeriodFilter: String, CaseIterable {
    case today = "今天"
    case thisWeek = "本周"
    case payCycle = "本周期"
    case thisMonth = "本月"
    case all = "全部"
    case custom = "自定义"

    var metricPrefix: String {
        switch self {
        case .today: return "今日"
        case .thisWeek: return "本周"
        case .payCycle: return "本周期"
        case .thisMonth: return "本月"
        case .all: return "全部"
        case .custom: return "所选范围"
        }
    }

    func dateRange(referenceDate: Date, payday: Int, customStart: Date, customEnd: Date, calendar: Calendar = .current) -> Range<Date>? {
        switch self {
        case .all: return nil
        case .today:
            let start = calendar.startOfDay(for: referenceDate)
            return start..<(calendar.date(byAdding: .day, value: 1, to: start) ?? referenceDate)
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: referenceDate).map { $0.start..<$0.end }
        case .payCycle:
            let cycle = PayCycleService.cycle(containing: referenceDate, payday: payday, calendar: calendar)
            return cycle.start..<cycle.end
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: referenceDate).map { $0.start..<$0.end }
        case .custom:
            let start = calendar.startOfDay(for: customStart)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEnd)) ?? start
            return min(start, end)..<max(start, end)
        }
    }
}

/// 账本列表里的一行交易。隐私锁生效时收入金额与受保护收入的元数据都要遮挡。
struct TransactionRow: View {
    let transaction: Transaction
    var revealsPrivateIncome = true
    var hidesIncome = false

    private var hidesPrivateIncome: Bool { transaction.isProtectedIncome && !revealsPrivateIncome }
    private var hidesIncomeAmount: Bool { hidesPrivateIncome || (hidesIncome && !transaction.isExpense) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(rowColor.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: hidesPrivateIncome ? "lock.fill" : transaction.category?.icon ?? "questionmark")
                    .font(.subheadline).foregroundStyle(rowColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(hidesPrivateIncome ? "隐私收入" : transaction.category?.entryDisplayName ?? "未分类")
                    .font(.subheadline.weight(.medium)).foregroundStyle(DesignSystem.textPrimary)
                if !hidesPrivateIncome && !transaction.note.isEmpty {
                    Text(transaction.note).font(.caption).foregroundStyle(DesignSystem.textTertiary).lineLimit(1)
                }
            }
            Spacer()
            Text(hidesIncomeAmount ? "****" : "\(transaction.isExpense ? "-" : "+")\(transaction.amount.formattedCompactAmount)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(transaction.isExpense ? DesignSystem.expenseColor : DesignSystem.incomeColor)
                .lineLimit(1).minimumScaleFactor(0.72).allowsTightening(true)
        }
        .padding(.vertical, 8).padding(.horizontal, 4)
    }

    private var rowColor: Color {
        hidesPrivateIncome ? DesignSystem.textTertiary : Color(hex: transaction.category?.colorHex ?? "#667EEA")
    }
}

/// 一枚可一键清除的生效筛选条件标签。
struct FilterChip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let label: String
    let color: Color
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(color)
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3)) { onRemove() }
                HapticManager.selection()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(color)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("移除筛选条件：\(label)")
                .accessibilityIdentifier("ledger.filterChip.\(label)")
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(color.opacity(0.12)).clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.2), lineWidth: 1))
        .transition(.scale.combined(with: .opacity))
    }
}
