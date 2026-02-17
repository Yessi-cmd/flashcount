import SwiftUI
import SwiftData

/// 添加周期性规则
struct AddRecurringRuleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Ledger.sortOrder) private var ledgers: [Ledger]
    @Query(filter: #Predicate<Category> { $0.isExpense == true && $0.isArchived == false }, sort: \Category.sortOrder) private var categories: [Category]

    @State private var title = ""
    @State private var amountText = ""
    @State private var frequency: RecurringFrequency = .monthly
    @State private var nextDueDate = Date()
    @State private var selectedCategory: Category?
    @State private var selectedLedger: Ledger?
    @State private var isExpense = true

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // 名称
                        VStack(alignment: .leading, spacing: 8) {
                            Text("名称").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
                            TextField("例如：房租、Netflix", text: $title).font(.body).foregroundStyle(.white)
                                .padding(12).background(.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                        }

                        // 金额
                        VStack(alignment: .leading, spacing: 8) {
                            Text("金额").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
                            HStack {
                                Text("¥").font(.title3).foregroundStyle(.white.opacity(0.5))
                                TextField("0.00", text: $amountText).keyboardType(.decimalPad)
                                    .font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(.white)
                            }
                            .padding(12).background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                        }

                        // 频率
                        VStack(alignment: .leading, spacing: 8) {
                            Text("频率").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
                            HStack(spacing: 8) {
                                ForEach(RecurringFrequency.allCases, id: \.rawValue) { freq in
                                    Button { frequency = freq } label: {
                                        Text(freq.rawValue).font(.caption.weight(.medium))
                                            .padding(.horizontal, 14).padding(.vertical, 8)
                                            .background(frequency == freq ? DesignSystem.primaryColor.opacity(0.2) : .white.opacity(0.06))
                                            .foregroundStyle(frequency == freq ? DesignSystem.primaryColor : .white.opacity(0.5))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }

                        // 下次日期
                        VStack(alignment: .leading, spacing: 8) {
                            Text("下次扣款日").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
                            DatePicker("", selection: $nextDueDate, displayedComponents: .date)
                                .datePickerStyle(.compact).labelsHidden().colorScheme(.dark)
                        }

                        // 分类
                        VStack(alignment: .leading, spacing: 8) {
                            Text("分类").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(categories, id: \.id) { cat in
                                        Button { selectedCategory = cat } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: cat.icon).font(.caption)
                                                Text(cat.name).font(.caption)
                                            }
                                            .padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(selectedCategory?.id == cat.id ? Color(hex: cat.colorHex).opacity(0.2) : .white.opacity(0.06))
                                            .foregroundStyle(selectedCategory?.id == cat.id ? Color(hex: cat.colorHex) : .white.opacity(0.5))
                                            .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                        }

                        // 账本
                        VStack(alignment: .leading, spacing: 8) {
                            Text("账本").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
                            HStack(spacing: 8) {
                                ForEach(ledgers, id: \.id) { ledger in
                                    Button { selectedLedger = ledger } label: {
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

                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle("添加周期账单").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() }.foregroundStyle(.white.opacity(0.7)) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { saveRule() }.disabled(title.isEmpty || amountText.isEmpty).foregroundStyle(DesignSystem.primaryColor)
                }
            }
            .onAppear {
                selectedLedger = ledgers.first(where: { $0.isDefault }) ?? ledgers.first
            }
        }
    }

    private func saveRule() {
        guard let amount = Decimal(string: amountText) else { return }
        let rule = RecurringRule(title: title, amount: amount, isExpense: isExpense, frequency: frequency,
                                nextDueDate: nextDueDate, category: selectedCategory, ledger: selectedLedger)
        modelContext.insert(rule); try? modelContext.save(); dismiss()
    }
}
