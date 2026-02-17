import SwiftUI
import SwiftData

/// 账本主页面 - 展示当前账本的交易列表和统计
struct LedgerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ledger.sortOrder) private var ledgers: [Ledger]
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]

    @State private var selectedLedger: Ledger?
    @State private var showAddTransaction = false
    @State private var showAddLedger = false
    @State private var showLedgerManager = false
    @State private var editingTransaction: Transaction?
    @State private var searchText = ""
    @State private var dateFilter: DateFilter = .all
    @State private var customStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    @State private var customEndDate = Date()

    enum DateFilter: String, CaseIterable {
        case all = "全部"
        case today = "今天"
        case thisWeek = "本周"
        case thisMonth = "本月"
        case custom = "自定义"
    }

    private var filteredTransactions: [Transaction] {
        var result = allTransactions
        if let ledger = selectedLedger {
            result = result.filter { $0.ledger?.id == ledger.id }
        }
        // 日期筛选
        let calendar = Calendar.current
        let now = Date()
        switch dateFilter {
        case .all: break
        case .today:
            let start = calendar.startOfDay(for: now)
            result = result.filter { $0.date >= start }
        case .thisWeek:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            result = result.filter { $0.date >= start }
        case .thisMonth:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
            result = result.filter { $0.date >= start }
        case .custom:
            let start = calendar.startOfDay(for: customStartDate)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEndDate))!
            result = result.filter { $0.date >= start && $0.date < end }
        }
        // 关键词搜索
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.note.lowercased().contains(query) ||
                $0.category?.name.lowercased().contains(query) == true ||
                "\($0.amount)".contains(query)
            }
        }
        return result
    }

    private var monthlyExpense: Decimal {
        let calendar = Calendar.current
        let now = Date()
        return filteredTransactions
            .filter { $0.isExpense && calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    private var monthlyIncome: Decimal {
        let calendar = Calendar.current
        let now = Date()
        return filteredTransactions
            .filter { !$0.isExpense && calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    /// 按日期分组的交易
    private var groupedTransactions: [(String, [Transaction])] {
        let grouped = Dictionary(grouping: filteredTransactions) { transaction -> String in
            transaction.date.relativeString
        }
        return grouped.sorted { a, b in
            let dateA = a.value.first?.date ?? Date()
            let dateB = b.value.first?.date ?? Date()
            return dateA > dateB
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DesignSystem.sectionSpacing) {
                        // 搜索栏
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.3))
                            TextField("搜索备注、分类、金额...", text: $searchText)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                            }
                        }
                        .padding(10)
                        .background(.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        // 日期筛选快捷标签
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(DateFilter.allCases, id: \.self) { filter in
                                    Button {
                                        withAnimation(.spring(response: 0.3)) { dateFilter = filter }
                                    } label: {
                                        Text(filter.rawValue)
                                            .font(.caption.weight(.medium))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(dateFilter == filter ? DesignSystem.primaryColor.opacity(0.2) : .white.opacity(0.06))
                                            .foregroundStyle(dateFilter == filter ? DesignSystem.primaryColor : .white.opacity(0.5))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }

                        // 自定义日期范围
                        if dateFilter == .custom {
                            HStack(spacing: 12) {
                                DatePicker("", selection: $customStartDate, displayedComponents: .date)
                                    .datePickerStyle(.compact).labelsHidden().colorScheme(.dark)
                                Text("→").foregroundStyle(.white.opacity(0.3))
                                DatePicker("", selection: $customEndDate, displayedComponents: .date)
                                    .datePickerStyle(.compact).labelsHidden().colorScheme(.dark)
                            }
                        }

                        // 账本选择器
                        ledgerPicker

                        // 本月概览卡片
                        monthlySummaryCard

                        // 交易列表
                        transactionList
                    }
                    .padding()
                }
            }
            .navigationTitle("账本")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showLedgerManager = true
                    } label: {
                        Image(systemName: "folder.badge.gearshape")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .sheet(isPresented: $showAddTransaction) {
                QuickEntryView()
            }
            .sheet(isPresented: $showAddLedger) {
                AddLedgerView()
            }
            .sheet(isPresented: $showLedgerManager) {
                LedgerManagerView()
            }
            .sheet(item: $editingTransaction) { transaction in
                EditTransactionView(transaction: transaction)
            }
            .onAppear {
                if selectedLedger == nil {
                    selectedLedger = ledgers.first(where: { $0.isDefault }) ?? ledgers.first
                }
            }
        }
    }

    // MARK: - Components

    private var ledgerPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ledgers, id: \.id) { ledger in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedLedger = ledger
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: ledger.icon)
                                .font(.subheadline)
                            Text(ledger.name)
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            selectedLedger?.id == ledger.id
                            ? Color(hex: ledger.colorHex).opacity(0.2)
                            : .white.opacity(0.06)
                        )
                        .foregroundStyle(
                            selectedLedger?.id == ledger.id
                            ? Color(hex: ledger.colorHex)
                            : .white.opacity(0.5)
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(
                                    selectedLedger?.id == ledger.id
                                    ? Color(hex: ledger.colorHex).opacity(0.4)
                                    : .clear,
                                    lineWidth: 1
                                )
                        )
                    }
                }

                // 添加账本按钮
                Button {
                    showAddLedger = true
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline)
                        .padding(10)
                        .background(.white.opacity(0.06))
                        .foregroundStyle(.white.opacity(0.4))
                        .clipShape(Circle())
                }
            }
        }
    }

    private var monthlySummaryCard: some View {
        VStack(spacing: 16) {
            // 月份标题
            HStack {
                Text(Date().monthYearString)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
            }

            HStack(spacing: 0) {
                // 支出
                VStack(alignment: .leading, spacing: 4) {
                    Text("支出")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    Text(monthlyExpense.formattedCurrency)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(DesignSystem.expenseColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 收入
                VStack(alignment: .leading, spacing: 4) {
                    Text("收入")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    Text(monthlyIncome.formattedCurrency)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(DesignSystem.incomeColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 结余
                VStack(alignment: .trailing, spacing: 4) {
                    Text("结余")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    Text((monthlyIncome - monthlyExpense).formattedCurrency)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(
                            monthlyIncome >= monthlyExpense
                            ? DesignSystem.incomeColor
                            : DesignSystem.expenseColor
                        )
                }
            }
        }
        .glassCard()
    }

    private var transactionList: some View {
        LazyVStack(spacing: 4) {
            if groupedTransactions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.2))
                    Text("暂无交易记录")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.4))
                    Button("记一笔") {
                        showAddTransaction = true
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.primaryColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            }

            ForEach(groupedTransactions, id: \.0) { dateString, transactions in
                Section {
                    ForEach(transactions, id: \.id) { transaction in
                        TransactionRow(transaction: transaction)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    withAnimation {
                                        modelContext.delete(transaction)
                                        try? modelContext.save()
                                    }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    editingTransaction = transaction
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                .tint(DesignSystem.primaryColor)
                            }
                    }
                } header: {
                    HStack {
                        Text(dateString)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.4))
                        Spacer()
                        let dayTotal = transactions.reduce(Decimal(0)) { $0 + $1.signedAmount }
                        Text(dayTotal.formattedCurrency)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 4)
                }
            }
        }
    }
}

/// 单笔交易行
struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            // 分类图标
            ZStack {
                Circle()
                    .fill(Color(hex: transaction.category?.colorHex ?? "#667EEA").opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: transaction.category?.icon ?? "questionmark")
                    .font(.subheadline)
                    .foregroundStyle(Color(hex: transaction.category?.colorHex ?? "#667EEA"))
            }

            // 分类名和备注
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.category?.name ?? "未分类")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                if !transaction.note.isEmpty {
                    Text(transaction.note)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }

            Spacer()

            // 金额
            Text("\(transaction.isExpense ? "-" : "+")\(transaction.amount.formattedAmount)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(
                    transaction.isExpense
                    ? DesignSystem.expenseColor
                    : DesignSystem.incomeColor
                )
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

/// 添加账本
struct AddLedgerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedIcon = "folder.fill"
    @State private var selectedColor = "#667EEA"

    private let icons = [
        "house.fill", "briefcase.fill", "airplane", "wrench.and.screwdriver.fill",
        "cart.fill", "heart.fill", "graduationcap.fill", "car.fill",
        "gift.fill", "gamecontroller.fill", "music.note", "fork.knife"
    ]

    private let colors = [
        "#667EEA", "#764BA2", "#F093FB", "#FC5C7D",
        "#FF6B6B", "#FFA502", "#2ED573", "#1E90FF",
        "#4ECDC4", "#A8E6CF", "#778BEB", "#E056A0"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()

                VStack(spacing: 24) {
                    // 名称输入
                    VStack(alignment: .leading, spacing: 8) {
                        Text("账本名称")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.5))
                        TextField("例如：旅行", text: $name)
                            .font(.title3)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                    }

                    // 图标选择
                    VStack(alignment: .leading, spacing: 8) {
                        Text("图标")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.5))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                            ForEach(icons, id: \.self) { icon in
                                Button {
                                    selectedIcon = icon
                                } label: {
                                    Image(systemName: icon)
                                        .font(.title3)
                                        .frame(width: 44, height: 44)
                                        .background(
                                            selectedIcon == icon
                                            ? Color(hex: selectedColor).opacity(0.2)
                                            : .white.opacity(0.06)
                                        )
                                        .foregroundStyle(
                                            selectedIcon == icon
                                            ? Color(hex: selectedColor)
                                            : .white.opacity(0.5)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }

                    // 颜色选择
                    VStack(alignment: .leading, spacing: 8) {
                        Text("颜色")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.5))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                            ForEach(colors, id: \.self) { color in
                                Button {
                                    selectedColor = color
                                } label: {
                                    Circle()
                                        .fill(Color(hex: color))
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            Circle()
                                                .stroke(.white, lineWidth: selectedColor == color ? 3 : 0)
                                                .padding(2)
                                        )
                                }
                            }
                        }
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("新建账本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        let ledger = Ledger(name: name, icon: selectedIcon, colorHex: selectedColor)
                        modelContext.insert(ledger)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .foregroundStyle(DesignSystem.primaryColor)
                }
            }
        }
    }
}

/// 账本管理页面
struct LedgerManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Ledger.sortOrder) private var ledgers: [Ledger]

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()

                List {
                    ForEach(ledgers, id: \.id) { ledger in
                        HStack(spacing: 12) {
                            Image(systemName: ledger.icon)
                                .foregroundStyle(Color(hex: ledger.colorHex))
                                .frame(width: 30)
                            Text(ledger.name)
                                .foregroundStyle(.white)
                            Spacer()
                            if ledger.isDefault {
                                Text("默认")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            Text("\(ledger.transactions.count) 笔")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .listRowBackground(Color.white.opacity(0.04))
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let ledger = ledgers[index]
                            if !ledger.isDefault {
                                modelContext.delete(ledger)
                            }
                        }
                        try? modelContext.save()
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("管理账本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(DesignSystem.primaryColor)
                }
            }
        }
    }
}
