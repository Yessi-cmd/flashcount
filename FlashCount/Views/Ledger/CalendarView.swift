import SwiftUI
import SwiftData

/// 日历视图 - 展示每日收支
struct CalendarView: View {
    @State private var displayedMonth = Date()
    @State private var selectedDate: Date?

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: DesignSystem.space16) {
            monthHeader
            CalendarMonthContent(displayedMonth: displayedMonth, selectedDate: $selectedDate)
                // 强制按月份重建 @Query，使切月直接下推到 SwiftData 查询。
                .id(calendar.startOfDay(for: displayedMonth))
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
                    .foregroundStyle(DesignSystem.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(DesignSystem.softFill)
                    .clipShape(Circle())
            }

            Spacer()

            Text(displayedMonth.monthYearString)
                .font(.headline.weight(.semibold))
                .foregroundStyle(DesignSystem.textPrimary)

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3)) {
                    displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                    selectedDate = nil
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(DesignSystem.softFill)
                    .clipShape(Circle())
            }
        }
    }
}

/// 指定月份的日历数据与内容。查询范围限定在该月，避免日历入口加载完整历史交易。
private struct CalendarMonthContent: View {
    @EnvironmentObject private var privacyLock: PrivacyLockService
    @Query private var monthTransactions: [Transaction]

    let displayedMonth: Date
    @Binding var selectedDate: Date?

    private var calendar: Calendar { Calendar.current }

    init(displayedMonth: Date, selectedDate: Binding<Date?>) {
        self.displayedMonth = displayedMonth
        _selectedDate = selectedDate

        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: displayedMonth)
        let start = interval?.start ?? displayedMonth
        let end = interval?.end ?? displayedMonth
        _monthTransactions = Query(
            filter: #Predicate<Transaction> { transaction in
                transaction.date >= start && transaction.date < end
            },
            sort: \Transaction.date,
            order: .reverse
        )
    }

    private struct MonthPresentation {
        struct DaySummary {
            var income: Decimal = 0
            var expense: Decimal = 0
            var hasHiddenIncome = false
            var netTotal: Decimal = 0
            var transactions: [Transaction] = []
        }

        let days: [Date: DaySummary]
        let income: Decimal
        let expense: Decimal
        let hasHiddenIncome: Bool

        init(transactions: [Transaction], calendar: Calendar, hidesIncome: Bool) {
            var days: [Date: DaySummary] = [:]
            var income: Decimal = 0
            var expense: Decimal = 0
            var hasHiddenIncome = false

            for transaction in transactions {
                let day = calendar.startOfDay(for: transaction.date)
                var summary = days[day] ?? DaySummary()
                summary.transactions.append(transaction)
                summary.netTotal += transaction.signedAmount

                if transaction.isExpense {
                    summary.expense += transaction.amount
                    expense += transaction.amount
                } else {
                    summary.income += transaction.amount
                    income += transaction.amount
                    if hidesIncome {
                        summary.hasHiddenIncome = true
                        hasHiddenIncome = true
                    }
                }
                days[day] = summary
            }

            self.days = days
            self.income = income
            self.expense = expense
            self.hasHiddenIncome = hasHiddenIncome
        }
    }

    private var daysInMonth: [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))
        else { return [] }
        return range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)
        }
    }

    private var firstWeekday: Int {
        guard let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))
        else { return 0 }
        return calendar.component(.weekday, from: firstOfMonth) - 1
    }

    var body: some View {
        let presentation = MonthPresentation(
            transactions: monthTransactions,
            calendar: calendar,
            hidesIncome: privacyLock.hidesSensitiveAmounts
        )

        return VStack(spacing: DesignSystem.space16) {
            weekdayHeader
            calendarGrid(presentation)
            monthSummary(presentation)
            if selectedDate != nil {
                selectedDateDetail(presentation)
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
                    .foregroundStyle(DesignSystem.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - 日历网格

    private func calendarGrid(_ presentation: MonthPresentation) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

        return LazyVGrid(columns: columns, spacing: 4) {
            // 空白填充
            ForEach(0..<firstWeekday, id: \.self) { _ in
                Color.clear.frame(height: 52)
            }

            // 每天的单元格
            ForEach(daysInMonth, id: \.self) { date in
                let summary = presentation.days[calendar.startOfDay(for: date)]
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
                                : DesignSystem.textPrimary
                            )

                        if let summary {
                            if summary.expense > 0 {
                                Text(summary.expense.compactAmount)
                                    .font(.system(size: 8).monospacedDigit())
                                    .foregroundStyle(DesignSystem.expenseColor.opacity(0.8))
                                    .lineLimit(1)
                            }
                            if summary.income > 0 && !summary.hasHiddenIncome {
                                Text(summary.income.compactAmount)
                                    .font(.system(size: 8).monospacedDigit())
                                    .foregroundStyle(DesignSystem.incomeColor.opacity(0.8))
                                    .lineLimit(1)
                            }
                            if summary.hasHiddenIncome {
                                Text("****")
                                    .font(.system(size: 8).monospacedDigit())
                                    .foregroundStyle(DesignSystem.textTertiary)
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
                                : summary != nil ? DesignSystem.softFill
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

    private func monthSummary(_ presentation: MonthPresentation) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("收入").font(.caption2).foregroundStyle(DesignSystem.textTertiary)
                Text(presentation.hasHiddenIncome ? privacyLock.maskedText : presentation.income.formattedCurrency)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(DesignSystem.incomeColor)
            }
            .frame(maxWidth: .infinity)

            Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 24)

            VStack(spacing: 2) {
                Text("支出").font(.caption2).foregroundStyle(DesignSystem.textTertiary)
                Text(presentation.expense.formattedCurrency)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(DesignSystem.expenseColor)
            }
            .frame(maxWidth: .infinity)

            Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 24)

            VStack(spacing: 2) {
                Text("结余").font(.caption2).foregroundStyle(DesignSystem.textTertiary)
                Text(presentation.hasHiddenIncome ? privacyLock.maskedText : (presentation.income - presentation.expense).formattedCurrency)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(presentation.hasHiddenIncome ? DesignSystem.textTertiary : (presentation.income >= presentation.expense ? DesignSystem.incomeColor : DesignSystem.expenseColor))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 10)
        .background(DesignSystem.softFill)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 选中日期详情

    private func selectedDateDetail(_ presentation: MonthPresentation) -> some View {
        let selectedSummary = selectedDate.flatMap { presentation.days[calendar.startOfDay(for: $0)] }

        return VStack(alignment: .leading, spacing: 8) {
            if let date = selectedDate {
                HStack {
                    Text(date.relativeString)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DesignSystem.textSecondary)
                    Spacer()
                    let dayTotal = selectedSummary?.netTotal ?? 0
                    Text(selectedSummary?.hasHiddenIncome == true ? privacyLock.maskedText : dayTotal.formattedCurrency)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(selectedSummary?.hasHiddenIncome == true ? DesignSystem.textTertiary : (dayTotal >= 0 ? DesignSystem.incomeColor : DesignSystem.expenseColor))
                }
            }

            if selectedSummary?.transactions.isEmpty ?? true {
                HStack {
                    Spacer()
                    Text("当天无交易记录")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textTertiary)
                    Spacer()
                }
                .padding(.vertical, 16)
            } else {
                ForEach(selectedSummary?.transactions ?? [], id: \.id) { transaction in
                    TransactionRow(
                        transaction: transaction,
                        revealsPrivateIncome: privacyLock.isUnlocked,
                        hidesIncome: privacyLock.hidesSensitiveAmounts
                    )
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
