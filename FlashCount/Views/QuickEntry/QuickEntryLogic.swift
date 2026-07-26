import SwiftUI
import SwiftData

// MARK: - 输入、分类选择与保存逻辑

extension QuickEntryView {
    /// 金额键交给 `QuickEntryAmountInput`（纯逻辑，位数限制与累加都在那边被单测）；
    /// 这里只负责收支切换和触感反馈。
    func handleKeyPress(_ key: String) {
        switch key {
        case "收入":
            // 这两个键紧贴数字 6 和 3，误触概率不低；至少要有触感回执，
            // 让用户知道刚刚切换的是收支类型而不是输错了数字。
            selectTransactionType(false)
        case "支出":
            selectTransactionType(true)
        default:
            amountError = nil
            switch amountInput.apply(key) {
            case .changed(let accumulated):
                if accumulated { HapticManager.impact(.light) }
            case .ignored:
                break
            case .rejected(let error):
                amountError = error
                HapticManager.error()
            }
        }
    }

    func clearPendingSum() {
        amountInput.clearPendingSum()
        amountError = nil
        HapticManager.selection()
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
            amountInput.replace(with: template.amount)
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
        switch amountInput.resolved() {
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
