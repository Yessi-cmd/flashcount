import SwiftUI
import SwiftData

/// 日历视图 - 展示每日收支
struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]

    @State private var displayedMonth = Date()
    @State private var selectedDate: Date?

    private var calendar: Calendar { Calendar.current }

    // 当月所有日期
    private var daysInMonth: [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))
        else { return [] }
        return range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)
        }
    }

    // 月份第一天是星期几（0=周日）
    private var firstWeekday: Int {
        guard let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))
        else { return 0 }
        return calendar.component(.weekday, from: firstOfMonth) - 1
    }

    // 按日期分组的交易汇总
    private var dailySummary: [String: (income: Decimal, expense: Decimal)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var result: [String: (income: Decimal, expense: Decimal)] = [:]

        // 只处理当月交易
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        let monthTransactions = allTransactions.filter {
            let tc = calendar.dateComponents([.year, .month], from: $0.date)
            return tc.year == components.year && tc.month == components.month
        }

        for t in monthTransactions {
            let key = formatter.string(from: t.date)
            var entry = result[key] ?? (income: 0, expense: 0)
            if t.isExpense {
                entry.expense += t.amount
            } else {
                entry.income += t.amount
            }
            result[key] = entry
        }
        return result
    }

    // 选中日期的交易列表
    private var selectedDateTransactions: [Transaction] {
        guard let date = selectedDate else { return [] }
        return allTransactions.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    var body: some View {
        VStack(spacing: 16) {
            // 月份导航
            monthHeader

            // 星期标题
            weekdayHeader

            // 日历网格
            calendarGrid

            // 月度汇总
            monthSummary

            // 选中日期的交易列表
            if selectedDate != nil {
                selectedDateDetail
            }
        }
    }

    // MARK: - 月份导航

    private var monthHeader: some View {
        HStack {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                    selectedDate = nil
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.06))
                    .clipShape(Circle())
            }

            Spacer()

            Text(displayedMonth.monthYearString)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3)) {
                    displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                    selectedDate = nil
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.06))
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - 星期标题

    private var weekdayHeader: some View {
        let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
        return HStack(spacing: 0) {
            ForEach(weekdays, id: \.self) { day in
                Text(day)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - 日历网格

    private var calendarGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        return LazyVGrid(columns: columns, spacing: 4) {
            // 空白填充
            ForEach(0..<firstWeekday, id: \.self) { _ in
                Color.clear.frame(height: 52)
            }

            // 每天的单元格
            ForEach(daysInMonth, id: \.self) { date in
                let key = formatter.string(from: date)
                let summary = dailySummary[key]
                let isToday = calendar.isDateInToday(date)
                let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false

                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedDate = isSelected ? nil : date
                    }
                } label: {
                    VStack(spacing: 2) {
                        Text("\(calendar.component(.day, from: date))")
                            .font(.caption.weight(isToday ? .bold : .regular))
                            .foregroundStyle(
                                isSelected ? .white
                                : isToday ? DesignSystem.primaryColor
                                : .white.opacity(0.8)
                            )

                        if let summary {
                            if summary.expense > 0 {
                                Text(summary.expense.compactAmount)
                                    .font(.system(size: 8).monospacedDigit())
                                    .foregroundStyle(DesignSystem.expenseColor.opacity(0.8))
                                    .lineLimit(1)
                            }
                            if summary.income > 0 {
                                Text(summary.income.compactAmount)
                                    .font(.system(size: 8).monospacedDigit())
                                    .foregroundStyle(DesignSystem.incomeColor.opacity(0.8))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                isSelected ? DesignSystem.primaryColor.opacity(0.3)
                                : isToday ? DesignSystem.primaryColor.opacity(0.08)
                                : summary != nil ? .white.opacity(0.03)
                                : .clear
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isSelected ? DesignSystem.primaryColor.opacity(0.6)
                                : isToday ? DesignSystem.primaryColor.opacity(0.3)
                                : .clear,
                                lineWidth: 1
                            )
                    )
                }
            }
        }
    }

    // MARK: - 月度汇总

    private var monthSummary: some View {
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        let monthTransactions = allTransactions.filter {
            let tc = calendar.dateComponents([.year, .month], from: $0.date)
            return tc.year == components.year && tc.month == components.month
        }
        let income = monthTransactions.filter { !$0.isExpense }.reduce(Decimal(0)) { $0 + $1.amount }
        let expense = monthTransactions.filter { $0.isExpense }.reduce(Decimal(0)) { $0 + $1.amount }

        return HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("收入").font(.caption2).foregroundStyle(.white.opacity(0.4))
                Text(income.formattedCurrency)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(DesignSystem.incomeColor)
            }
            .frame(maxWidth: .infinity)

            Rectangle().fill(.white.opacity(0.1)).frame(width: 1, height: 24)

            VStack(spacing: 2) {
                Text("支出").font(.caption2).foregroundStyle(.white.opacity(0.4))
                Text(expense.formattedCurrency)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(DesignSystem.expenseColor)
            }
            .frame(maxWidth: .infinity)

            Rectangle().fill(.white.opacity(0.1)).frame(width: 1, height: 24)

            VStack(spacing: 2) {
                Text("结余").font(.caption2).foregroundStyle(.white.opacity(0.4))
                Text((income - expense).formattedCurrency)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(income >= expense ? DesignSystem.incomeColor : DesignSystem.expenseColor)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 10)
        .background(.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 选中日期详情

    private var selectedDateDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let date = selectedDate {
                HStack {
                    Text(date.relativeString)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    let dayTotal = selectedDateTransactions.reduce(Decimal(0)) { $0 + $1.signedAmount }
                    Text(dayTotal.formattedCurrency)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(dayTotal >= 0 ? DesignSystem.incomeColor : DesignSystem.expenseColor)
                }
            }

            if selectedDateTransactions.isEmpty {
                HStack {
                    Spacer()
                    Text("当天无交易记录")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                    Spacer()
                }
                .padding(.vertical, 16)
            } else {
                ForEach(selectedDateTransactions, id: \.id) { transaction in
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: transaction.category?.colorHex ?? "#667EEA").opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: transaction.category?.icon ?? "questionmark")
                                .font(.caption)
                                .foregroundStyle(Color(hex: transaction.category?.colorHex ?? "#667EEA"))
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(transaction.category?.name ?? "未分类")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white)
                            if !transaction.note.isEmpty {
                                Text(transaction.note)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.4))
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        Text("\(transaction.isExpense ? "-" : "+")\(transaction.amount.formattedAmount)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(
                                transaction.isExpense ? DesignSystem.expenseColor : DesignSystem.incomeColor
                            )
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .glassCard()
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Decimal 紧凑显示扩展

extension Decimal {
    /// 紧凑金额显示（日历格子用）
    var compactAmount: String {
        let d = NSDecimalNumber(decimal: self).doubleValue
        if d >= 10000 {
            return String(format: "%.0fw", d / 10000)
        } else if d >= 1000 {
            return String(format: "%.0fk", d / 1000)
        } else {
            return String(format: "%.0f", d)
        }
    }
}
