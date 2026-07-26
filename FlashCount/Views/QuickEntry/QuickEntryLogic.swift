import SwiftUI
import SwiftData

// MARK: - 输入、分类选择与保存逻辑

extension QuickEntryView {
    func handleKeyPress(_ key: String) {
        let maxIntegerDigits = 12  // 最大整数位数（万亿级别）
        amountError = nil

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
        case "收入":
            selectTransactionType(false, providesHaptic: false)
        case "支出":
            selectTransactionType(true, providesHaptic: false)
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

    func selectTransactionType(_ expense: Bool, providesHaptic: Bool = true) {
        withAnimation(reduceMotion ? nil : DesignSystem.glassSelectionAnimation) {
            isExpense = expense
        }
        selectedCategory = defaultCategory(
            from: expense ? expenseCategories : incomeCategories,
            isExpense: expense
        )
        dailyBudgetOverride = nil
        showAllCategories = false
        if providesHaptic {
            HapticManager.selection()
        }
    }

    func selectCategory(_ category: Category) {
        let rootName = category.rootCategoryName
        let target = category.name == rootName
            ? lastUsedCategory(for: rootName, in: currentCategories, isExpense: isExpense) ?? rootCategory(for: rootName, in: currentCategories) ?? category
            : category

        withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
            selectedCategory = target
            dailyBudgetOverride = nil
            showAllCategories = false
        }
        HapticManager.selection()
    }

    func selectExactCategory(_ category: Category) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
            selectedCategory = category
            dailyBudgetOverride = nil
            wheelCategory = nil
            wheelSourceFrame = nil
            showAllCategories = false
        }
    }

    func showWheel(for category: Category, sourceFrame: CGRect?) {
        let children = Category.childCategories(for: category.rootCategoryName, in: currentCategories, isExpense: isExpense)
        guard !children.isEmpty else {
            selectCategory(category)
            return
        }
        wheelSourceFrame = sourceFrame
        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82, blendDuration: 0.08)) {
            wheelCategory = category
        }
    }

    func categoryWheel(for category: Category) -> some View {
        let rootName = category.rootCategoryName
        let children = Category.childCategories(for: rootName, in: currentCategories, isExpense: isExpense)
        return CategoryWheelOverlay(
            parentCategory: rootCategory(for: rootName, in: currentCategories) ?? category,
            children: children,
            selectedCategory: selectedCategory,
            sourceFrame: wheelSourceFrame,
            onSelectParent: {
                if let root = rootCategory(for: rootName, in: currentCategories) {
                    selectExactCategory(root)
                } else {
                    selectExactCategory(category)
                }
            },
            onSelectChild: { child in
                selectExactCategory(child)
            },
            onDismiss: {
                withAnimation(reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.9)) {
                    wheelCategory = nil
                    wheelSourceFrame = nil
                }
            }
        )
    }

#if DEBUG
    func categoryMenuReviewCategory(arguments: [String]) -> Category? {
        let requestedName = arguments
            .first(where: { $0.hasPrefix("-visualCategoryMenuReview=") })?
            .split(separator: "=", maxSplits: 1)
            .last
            .map(String.init)

        if let requestedName,
           let requested = rootCategories.first(where: { $0.rootCategoryName == requestedName }) {
            return requested
        }
        return rootCategories.first
    }
#endif

    func defaultCategory(from categories: [Category], isExpense targetIsExpense: Bool) -> Category? {
        let roots = Category.rootCategories(from: categories, isExpense: targetIsExpense)
        guard let firstRoot = roots.first else { return categories.first }
        return lastUsedCategory(for: firstRoot.rootCategoryName, in: categories, isExpense: targetIsExpense)
            ?? rootCategory(for: firstRoot.rootCategoryName, in: categories)
            ?? firstRoot
    }

    func categoryRepresentative(for rootName: String) -> Category? {
        rootCategory(for: rootName, in: currentCategories)
            ?? currentCategories.first { $0.rootCategoryName == rootName }
    }

    func rootCategory(for rootName: String, in categories: [Category]) -> Category? {
        categories.first { $0.name == rootName && !$0.isArchived }
    }

    func lastUsedCategory(for rootName: String, in categories: [Category], isExpense targetIsExpense: Bool) -> Category? {
        let categoryIDs = Set(categories.map(\.id))
        return recentTransactions.first { transaction in
            guard transaction.isExpense == targetIsExpense, let category = transaction.category else { return false }
            return categoryIDs.contains(category.id) && category.rootCategoryName == rootName
        }?.category
    }

    /// 应用模板 — 一键填入金额 / 分类 / 备注 / 收支类型
    func applyTemplate(_ template: TransactionTemplate, category: Category?) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
            amountText = String(describing: template.amount)
            isExpense = template.isExpense
            note = template.note
            selectedCategory = category
            dailyBudgetOverride = nil
            showAllCategories = false
        }
        HapticManager.impact(.light)
    }

    func saveTransaction() {
        guard !isSaving else { return }
        let amount: Decimal
        switch MoneyValidation.parse(amountText, requirement: .positive) {
        case .success(let value):
            amount = value
            amountError = nil
        case .failure(let error):
            amountError = error
            HapticManager.error()
            return
        }
        isSaving = true
        defer { isSaving = false }

        let draft = TransactionDraft(
            amount: amount,
            isExpense: isExpense,
            note: note,
            date: selectedDate,
            dailyBudgetOverride: dailyBudgetOverride,
            category: selectedCategory,
            ledger: selectedLedger
        )
        let transaction: Transaction
        do {
            transaction = try TransactionMutationService(modelContext: modelContext).create(draft)
        } catch {
            saveError = error.localizedDescription
            HapticManager.error()
            return
        }

        HapticManager.success()
        updateBudgetReminder(afterSaving: transaction)

        withAnimation(reduceMotion ? nil : .spring(response: 0.4)) {
            showSuccess = true
        }
    }

    func resetForm() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
            amountText = ""
            amountError = nil
            note = ""
            showNote = false
            showSuccess = false
            budgetReminderText = nil
            budgetReminderLevel = nil
            dailyBudgetOverride = nil
        }
    }

    func updateBudgetReminder(afterSaving transaction: Transaction) {
        budgetReminderText = nil
        budgetReminderLevel = nil
        guard transaction.isExpense else { return }

        let cycle = PayCycleService.cycle(containing: transaction.date, payday: payday)
        let cycleStart = cycle.start
        let cycleEnd = cycle.end
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { item in
                item.date >= cycleStart && item.date < cycleEnd
            },
            sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
        )

        let transactions: [Transaction]
        do {
            transactions = try modelContext.fetch(descriptor)
        } catch {
            return
        }

        if let categorySnapshot = CategoryBudgetService.snapshot(
            for: transaction,
            budgets: allBudgets,
            transactions: transactions,
            categories: expenseCategories,
            ledger: nil,
            payday: payday,
            weekendMultiplier: WeekendBudgetPreferences.multiplier(for: weekendBudgetMultiplierPercent)
        ), categorySnapshot.alertLevel != .healthy {
            budgetReminderText = categorySnapshot.shortMessage
            budgetReminderLevel = categorySnapshot.alertLevel
            return
        }

        guard let reminder = BudgetReminderService.reminder(
            budgets: allBudgets,
            transactions: transactions,
            ledger: nil,
            referenceDate: transaction.date,
            payday: payday,
            weekendMultiplier: WeekendBudgetPreferences.multiplier(for: weekendBudgetMultiplierPercent)
        ), reminder.shouldSurfaceAfterSave else { return }

        budgetReminderText = reminder.shortMessage
        budgetReminderLevel = reminder.alertLevel
    }
}
