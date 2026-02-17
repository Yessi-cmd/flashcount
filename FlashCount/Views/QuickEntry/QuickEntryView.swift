import SwiftUI
import SwiftData

/// 极速记账页面 - 打开即可记账，3秒完成
struct QuickEntryView: View {
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

    @State private var amountText = ""
    @State private var isExpense = true
    @State private var selectedCategory: Category?
    @State private var selectedLedger: Ledger?
    @State private var note = ""
    @State private var selectedDate = Date()
    @State private var showDatePicker = false
    @State private var showSuccess = false
    @State private var showNote = false
    @State private var saveError: String?

    private var currentCategories: [Category] {
        isExpense ? expenseCategories : incomeCategories
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                DesignSystem.surfaceBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // 收入/支出切换
                        typeToggle

                        // 金额显示
                        amountDisplay

                        // 分类选择
                        categoryGrid

                        // 备注 & 日期
                        if showNote {
                            noteField
                        }

                        // 账本选择
                        ledgerSelector

                        // 数字键盘
                        numberPad

                        // 提交按钮
                        submitButton
                    }
                    .padding()
                }
            }
            .navigationTitle("记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNote.toggle()
                    } label: {
                        Image(systemName: "note.text")
                            .foregroundStyle(showNote ? DesignSystem.primaryColor : .white.opacity(0.5))
                    }
                }
            }
            .overlay {
                if showSuccess {
                    successOverlay
                }
            }
            .onAppear {
                // 默认选中默认账本
                if selectedLedger == nil {
                    selectedLedger = ledgers.first(where: { $0.isDefault }) ?? ledgers.first
                }
                // 默认选中第一个分类
                if selectedCategory == nil {
                    selectedCategory = currentCategories.first
                }
            }
            .saveErrorAlert($saveError)
        }
    }

    // MARK: - Components

    private var typeToggle: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3)) { isExpense = true }
                selectedCategory = expenseCategories.first
            } label: {
                Text("支出")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isExpense ? DesignSystem.expenseColor.opacity(0.2) : .clear)
                    .foregroundStyle(isExpense ? DesignSystem.expenseColor : .white.opacity(0.5))
            }

            Button {
                withAnimation(.spring(response: 0.3)) { isExpense = false }
                selectedCategory = incomeCategories.first
            } label: {
                Text("收入")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(!isExpense ? DesignSystem.incomeColor.opacity(0.2) : .clear)
                    .foregroundStyle(!isExpense ? DesignSystem.incomeColor : .white.opacity(0.5))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var amountDisplay: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("¥")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
                Text(amountText.isEmpty ? "0.00" : amountText)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }

            // 日期选择器 - 始终可见，方便补录历史账单
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .colorScheme(.dark)
                    .scaleEffect(0.85)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
            ForEach(currentCategories, id: \.id) { category in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedCategory = category
                    }
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(
                                    selectedCategory?.id == category.id
                                    ? Color(hex: category.colorHex).opacity(0.3)
                                    : .white.opacity(0.06)
                                )
                                .frame(width: 48, height: 48)

                            if selectedCategory?.id == category.id {
                                Circle()
                                    .stroke(Color(hex: category.colorHex), lineWidth: 2)
                                    .frame(width: 48, height: 48)
                            }

                            Image(systemName: category.icon)
                                .font(.title3)
                                .foregroundStyle(Color(hex: category.colorHex))
                        }

                        Text(category.name)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }
        }
        .glassCard()
    }

    private var noteField: some View {
        HStack {
            Image(systemName: "pencil")
                .foregroundStyle(.white.opacity(0.4))
            TextField("添加备注...", text: $note)
                .foregroundStyle(.white)
                .font(.subheadline)
        }
        .padding(12)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var ledgerSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ledgers, id: \.id) { ledger in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedLedger = ledger
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: ledger.icon)
                                .font(.caption)
                            Text(ledger.name)
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
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
                                    ? Color(hex: ledger.colorHex).opacity(0.5)
                                    : .clear,
                                    lineWidth: 1
                                )
                        )
                    }
                }
            }
        }
    }

    private var numberPad: some View {
        let buttons = [
            ["7", "8", "9", "⌫"],
            ["4", "5", "6", "+"],
            ["1", "2", "3", "-"],
            [".", "0", "00", ""]
        ]

        return VStack(spacing: 8) {
            ForEach(buttons, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { button in
                        if button.isEmpty {
                            Color.clear.frame(height: 50)
                        } else {
                            Button {
                                handleKeyPress(button)
                            } label: {
                                Text(button)
                                    .font(.title3.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(.white.opacity(button == "⌫" ? 0.08 : 0.04))
                                    .foregroundStyle(
                                        button == "⌫" ? .white.opacity(0.6)
                                        : button == "+" ? DesignSystem.incomeColor
                                        : button == "-" ? DesignSystem.expenseColor
                                        : .white
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
            }
        }
    }

    private var submitButton: some View {
        Button {
            saveTransaction()
        } label: {
            Text("保存")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    amountText.isEmpty
                    ? AnyShapeStyle(.gray.opacity(0.3))
                    : isExpense
                        ? AnyShapeStyle(DesignSystem.expenseGradient)
                        : AnyShapeStyle(DesignSystem.incomeGradient)
                )
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        }
        .disabled(amountText.isEmpty)
    }

    private var successOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(DesignSystem.incomeColor)
                .symbolEffect(.bounce, value: showSuccess)

            Text("记账成功！")
                .font(.headline)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .transition(.opacity)
    }

    // MARK: - Logic

    private func handleKeyPress(_ key: String) {
        let maxIntegerDigits = 12  // 最大整数位数（万亿级别）

        switch key {
        case "⌫":
            if !amountText.isEmpty {
                amountText.removeLast()
            }
        case ".":
            if !amountText.contains(".") {
                amountText += amountText.isEmpty ? "0." : "."
            }
        case "00":
            let intPart = amountText.split(separator: ".").first.map(String.init) ?? amountText
            if intPart.count >= maxIntegerDigits { return }
            if !amountText.isEmpty && !amountText.contains(".") {
                amountText += "00"
            } else if amountText.contains(".") {
                let parts = amountText.split(separator: ".")
                if parts.count < 2 || parts[1].count < 2 {
                    amountText += "0"
                }
            }
        case "+":
            withAnimation(.spring(response: 0.3)) { isExpense = false }
            selectedCategory = incomeCategories.first
        case "-":
            withAnimation(.spring(response: 0.3)) { isExpense = true }
            selectedCategory = expenseCategories.first
        default:
            // 限制整数部分最多 12 位
            let intPart = amountText.split(separator: ".").first.map(String.init) ?? amountText
            if !amountText.contains(".") && intPart.count >= maxIntegerDigits { return }
            // 限制小数点后两位
            if amountText.contains(".") {
                let parts = amountText.split(separator: ".")
                if parts.count >= 2 && parts[1].count >= 2 {
                    return
                }
            }
            amountText += key
        }
    }

    private func saveTransaction() {
        guard let amount = Decimal(string: amountText), amount > 0 else { return }

        let transaction = Transaction(
            amount: amount,
            isExpense: isExpense,
            note: note,
            date: selectedDate,
            category: selectedCategory,
            ledger: selectedLedger
        )
        modelContext.insert(transaction)

        if let error = safeSave(modelContext) {
            saveError = error
            HapticManager.error()
            return
        }

        HapticManager.success()

        // 成功动画
        withAnimation(.spring(response: 0.4)) {
            showSuccess = true
        }

        // 1秒后自动关闭页面
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            dismiss()
        }
    }
}
