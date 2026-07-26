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
            // 这两个键紧贴数字 6 和 3，误触概率不低；至少要有触感回执，
            // 让用户知道刚刚切换的是收支类型而不是输错了数字。
            selectTransactionType(false)
        case "支出":
            selectTransactionType(true)
        case "+":
            accumulateAmount()
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

    /// 「+」把当前输入折进累加值，显示区随即清零等下一笔。
    /// 拆账、凑总额是记账最常见的算术，此前键盘右下角是个空键位。
    func accumulateAmount() {
        switch MoneyValidation.parse(amountText, requirement: .positive) {
        case .success(let value):
            pendingSum += value
            amountText = ""
            amountError = nil
            HapticManager.impact(.light)
        case .failure(let error):
            // 已有累加值时空按一下「+」是无意义但无害的，不该报错。
            guard !(pendingSum > 0 && amountText.isEmpty) else { return }
            amountError = error
            HapticManager.error()
        }
    }

    func clearPendingSum() {
        pendingSum = 0
        amountError = nil
        HapticManager.selection()
    }

    /// 保存用的金额 = 已累加部分 + 当前输入。两者都空才算没填。
    func resolvedAmount() -> Result<Decimal, MoneyValidationError> {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return pendingSum > 0 ? .success(pendingSum) : .failure(.empty)
        }
        switch MoneyValidation.parse(trimmed, requirement: .positive) {
        case .success(let value):
            return .success(pendingSum + value)
        case .failure(let error):
            return .failure(error)
        }
    }

    func selectTransactionType(_ expense: Bool, providesHaptic: Bool = true) {
        guard isExpense != expense else {
            if providesHaptic { HapticManager.selection() }
            return
        }
        rememberSelectedCategory()
        withAnimation(reduceMotion ? nil : DesignSystem.glassSelectionAnimation) {
            isExpense = expense
        }
        let remembered = expense ? rememberedExpenseCategory : rememberedIncomeCategory
        selectedCategory = remembered ?? defaultCategory(
            from: expense ? expenseCategories : incomeCategories,
            isExpense: expense
        )
        dailyBudgetOverride = nil
        showAllCategories = false
        if providesHaptic {
            HapticManager.selection()
        }
    }

    /// 把当前这一侧的选择记下来，切回来时原样恢复。
    func rememberSelectedCategory() {
        guard let selectedCategory else { return }
        if isExpense {
            rememberedExpenseCategory = selectedCategory
        } else {
            rememberedIncomeCategory = selectedCategory
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
        rememberSelectedCategory()
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
        rememberSelectedCategory()
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
            pendingSum = 0
            isExpense = template.isExpense
            note = template.note
            selectedCategory = category
            dailyBudgetOverride = nil
            showAllCategories = false
        }
        rememberSelectedCategory()
        HapticManager.impact(.light)
    }

    func saveTransaction() {
        guard !isSaving else { return }
        let amount: Decimal
        switch resolvedAmount() {
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

        let reminder = budgetReminder(afterSaving: transaction)
        feedback.present(
            QuickEntryFeedbackCenter.SavedEntry(
                transactionID: transaction.persistentModelID,
                amount: amount,
                isExpense: isExpense,
                categoryName: selectedCategory?.entryDisplayName ?? "未分类",
                backdatedText: isBackdated ? "补录 \(selectedDate.shortDateString)" : nil,
                budgetReminder: reminder?.text,
                budgetAlertLevel: reminder?.level
            )
        )
        dismiss()
    }

    /// 保存后的预算提醒。过去它只画在全屏成功页上，现在跟着提示条一起走。
    func budgetReminder(afterSaving transaction: Transaction) -> (text: String, level: BudgetAlertLevel)? {
        guard transaction.isExpense else { return nil }

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
            return nil
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
            return (categorySnapshot.shortMessage, categorySnapshot.alertLevel)
        }

        guard let reminder = BudgetReminderService.reminder(
            budgets: allBudgets,
            transactions: transactions,
            ledger: nil,
            referenceDate: transaction.date,
            payday: payday,
            weekendMultiplier: WeekendBudgetPreferences.multiplier(for: weekendBudgetMultiplierPercent)
        ), reminder.shouldSurfaceAfterSave else { return nil }

        return (reminder.shortMessage, reminder.alertLevel)
    }
}
