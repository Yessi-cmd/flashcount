import SwiftUI
import SwiftData

/// 编辑交易记录
struct EditTransactionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Ledger.sortOrder) private var ledgers: [Ledger]
    @Query(
        filter: #Predicate<Category> { $0.isExpense == true && $0.isArchived == false },
        sort: \Category.sortOrder
    ) private var expenseCategories: [Category]
    @Query(
        filter: #Predicate<Category> { $0.isExpense == false && $0.isArchived == false },
        sort: \Category.sortOrder
    ) private var incomeCategories: [Category]

    @Bindable var transaction: Transaction

    @State private var amountText: String
    @State private var isExpense: Bool
    @State private var note: String
    @State private var selectedDate: Date
    @State private var selectedCategory: Category?
    @State private var selectedLedger: Ledger?
    @State private var saveError: String?

    init(transaction: Transaction) {
        self.transaction = transaction
        _amountText = State(initialValue: "\(transaction.amount)")
        _isExpense = State(initialValue: transaction.isExpense)
        _note = State(initialValue: transaction.note)
        _selectedDate = State(initialValue: transaction.date)
        _selectedCategory = State(initialValue: transaction.category)
        _selectedLedger = State(initialValue: transaction.ledger)
    }

    private var currentCategories: [Category] {
        isExpense ? expenseCategories : incomeCategories
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // 收支切换
                        HStack(spacing: 0) {
                            Button {
                                withAnimation(.spring(response: 0.3)) { isExpense = true }
                                selectedCategory = expenseCategories.first
                            } label: {
                                Text("支出").font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(isExpense ? DesignSystem.expenseColor.opacity(0.2) : .clear)
                                    .foregroundStyle(isExpense ? DesignSystem.expenseColor : .white.opacity(0.5))
                            }
                            Button {
                                withAnimation(.spring(response: 0.3)) { isExpense = false }
                                selectedCategory = incomeCategories.first
                            } label: {
                                Text("收入").font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(!isExpense ? DesignSystem.incomeColor.opacity(0.2) : .clear)
                                    .foregroundStyle(!isExpense ? DesignSystem.incomeColor : .white.opacity(0.5))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                        .overlay(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius).stroke(.white.opacity(0.1), lineWidth: 1))

                        // 金额
                        VStack(alignment: .leading, spacing: 8) {
                            Text("金额").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
                            HStack {
                                Text("¥").font(.title3).foregroundStyle(.white.opacity(0.5))
                                TextField("0.00", text: $amountText)
                                    .keyboardType(.decimalPad)
                                    .font(.title2.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(.white)
                            }
                            .padding(12).background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                        }

                        // 分类
                        VStack(alignment: .leading, spacing: 8) {
                            Text("分类").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                                ForEach(currentCategories, id: \.id) { category in
                                    Button {
                                        withAnimation(.spring(response: 0.3)) { selectedCategory = category }
                                    } label: {
                                        VStack(spacing: 6) {
                                            ZStack {
                                                Circle()
                                                    .fill(selectedCategory?.id == category.id
                                                          ? Color(hex: category.colorHex).opacity(0.3)
                                                          : .white.opacity(0.06))
                                                    .frame(width: 44, height: 44)
                                                if selectedCategory?.id == category.id {
                                                    Circle().stroke(Color(hex: category.colorHex), lineWidth: 2)
                                                        .frame(width: 44, height: 44)
                                                }
                                                Image(systemName: category.icon).font(.subheadline)
                                                    .foregroundStyle(Color(hex: category.colorHex))
                                            }
                                            Text(category.name).font(.caption2)
                                                .foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }

                        // 备注
                        VStack(alignment: .leading, spacing: 8) {
                            Text("备注").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
                            TextField("添加备注...", text: $note).font(.subheadline).foregroundStyle(.white)
                                .padding(12).background(.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                        }

                        // 日期
                        VStack(alignment: .leading, spacing: 8) {
                            Text("日期").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
                            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                                .datePickerStyle(.compact).labelsHidden().colorScheme(.dark)
                        }

                        // 账本
                        VStack(alignment: .leading, spacing: 8) {
                            Text("账本").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(ledgers, id: \.id) { ledger in
                                        Button {
                                            selectedLedger = ledger
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: ledger.icon).font(.caption)
                                                Text(ledger.name).font(.caption)
                                            }
                                            .padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(selectedLedger?.id == ledger.id ? Color(hex: ledger.colorHex).opacity(0.2) : .white.opacity(0.06))
                                            .foregroundStyle(selectedLedger?.id == ledger.id ? Color(hex: ledger.colorHex) : .white.opacity(0.5))
                                            .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                        }

                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle("编辑记录").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }.foregroundStyle(.white.opacity(0.7))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { saveChanges() }
                        .disabled(amountText.isEmpty)
                        .foregroundStyle(DesignSystem.primaryColor)
                }
            }
            .saveErrorAlert($saveError)
        }
    }

    private func saveChanges() {
        guard let amount = Decimal(string: amountText), amount > 0 else { return }
        transaction.amount = amount
        transaction.isExpense = isExpense
        transaction.note = note
        transaction.date = selectedDate
        transaction.category = selectedCategory
        transaction.ledger = selectedLedger

        if let error = safeSave(modelContext) {
            saveError = error
            HapticManager.error()
            return
        }
        HapticManager.success()
        dismiss()
    }
}
