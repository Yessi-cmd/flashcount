import SwiftUI
import SwiftData

// MARK: - 记账页各区块视图

extension QuickEntryView {
    var ledgerMenu: some View {
        Menu {
            ForEach(ledgers, id: \.id) { ledger in
                Button {
                    selectedLedger = ledger
                    HapticManager.selection()
                } label: {
                    Label(ledger.name, systemImage: selectedLedger?.id == ledger.id ? "checkmark.circle.fill" : ledger.icon)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: selectedLedger?.icon ?? "book.closed")
                    .font(.caption)
                Text(selectedLedger?.name ?? "账本")
                    .font(DesignSystem.Typography.compactLabel)
                    .lineLimit(1)
            }
            .foregroundStyle(DesignSystem.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(DesignSystem.softFill)
            .clipShape(Capsule())
        }
    }

    @ViewBuilder
    var typeToggle: some View {
        if #available(iOS 26.0, *) {
            liquidGlassTypeToggle
        } else {
            legacyTypeToggle
        }
    }

    @available(iOS 26.0, *)
    private var liquidGlassTypeToggle: some View {
        LiquidGlassContainer(spacing: 6) {
            HStack(spacing: 6) {
                liquidGlassTypeButton(title: "支出", expense: true, color: DesignSystem.expenseColor)
                liquidGlassTypeButton(title: "收入", expense: false, color: DesignSystem.incomeColor)
            }
        }
    }

    @available(iOS 26.0, *)
    private func liquidGlassTypeButton(title: String, expense: Bool, color: Color) -> some View {
        let isSelected = isExpense == expense
        return Button {
            selectTransactionType(expense)
        } label: {
            Text(title)
                .font(DesignSystem.Typography.controlLabel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(isSelected ? color : DesignSystem.textSecondary)
                .contentShape(Rectangle())
                .liquidGlassSurface(
                    tint: isSelected ? color.opacity(0.20) : nil,
                    shape: .roundedRectangle(13),
                    isInteractive: true,
                    isClear: !isSelected
                )
                .animation(reduceMotion ? nil : DesignSystem.glassSelectionAnimation, value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var legacyTypeToggle: some View {
        HStack(spacing: 0) {
            Button {
                selectTransactionType(true)
            } label: {
                Text("支出")
                    .font(DesignSystem.Typography.controlLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if isExpense {
                            RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius)
                                .fill(DesignSystem.expenseColor.opacity(0.18))
                                .matchedGeometryEffect(id: "quickEntryTypeSelection", in: typeSelectionNamespace)
                        }
                    }
                    .foregroundStyle(isExpense ? DesignSystem.expenseColor : DesignSystem.textSecondary)
            }

            Button {
                selectTransactionType(false)
            } label: {
                Text("收入")
                    .font(DesignSystem.Typography.controlLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if !isExpense {
                            RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius)
                                .fill(DesignSystem.incomeColor.opacity(0.18))
                                .matchedGeometryEffect(id: "quickEntryTypeSelection", in: typeSelectionNamespace)
                        }
                    }
                    .foregroundStyle(!isExpense ? DesignSystem.incomeColor : DesignSystem.textSecondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius)
                .stroke(DesignSystem.borderColor, lineWidth: 1)
        )
    }

    var amountDisplay: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("¥")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(DesignSystem.textSecondary)
                Text(amountText.isEmpty ? "0.00" : amountText)
                    .font(DesignSystem.Typography.amount)
                    .monospacedDigit()
                    .foregroundStyle(DesignSystem.textPrimary)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("quickEntry.amount")
            }

            if pendingSum > 0 {
                pendingSumChip
            }

            ValidationMessage(message: amountError?.errorDescription)

            dateControls
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    /// 累加中的提示：不显示出来，用户按了「+」之后只会看到金额被清空。
    private var pendingSumChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.forwardslash.minus")
                .font(.caption2.weight(.semibold))
            Text("已累加 \(pendingSum.formattedCurrency)，保存时合计 \(pendingTotalPreview.formattedCurrency)")
                .font(DesignSystem.Typography.supportingLabel)
                .monospacedDigit()
            Button {
                clearPendingSum()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("清除已累加金额")
        }
        .foregroundStyle(DesignSystem.primaryColor)
        .padding(.leading, 10)
        .background(DesignSystem.primaryColor.opacity(0.1))
        .clipShape(Capsule())
        .accessibilityIdentifier("quickEntry.pendingSum")
    }

    private var pendingTotalPreview: Decimal {
        switch resolvedAmount() {
        case .success(let value): return value
        case .failure: return pendingSum
        }
    }

    /// 日期区：以前只有一个被 `scaleEffect(0.8)` 缩到 44pt 以下的选择器，
    /// 既难点又太安静——补录时最需要的是一眼看出「这不是今天」。
    private var dateControls: some View {
        HStack(spacing: 8) {
            dateChip(title: "今天", date: Calendar.current.startOfDay(for: Date()))
            dateChip(
                title: "昨天",
                date: Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
            )

            DatePicker("记账日期", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .accessibilityIdentifier("quickEntry.datePicker")
        }
        .frame(minHeight: 44)
    }

    private func dateChip(title: String, date: Date) -> some View {
        let isSelected = Calendar.current.isDate(selectedDate, inSameDayAs: date)
        return Button {
            withAnimation(reduceMotion ? nil : DesignSystem.quickAnimation) {
                selectedDate = date
            }
            HapticManager.selection()
        } label: {
            Text(title)
                .font(DesignSystem.Typography.compactLabel)
                .foregroundStyle(isSelected ? DesignSystem.primaryColor : DesignSystem.textSecondary)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(isSelected ? DesignSystem.primaryColor.opacity(0.14) : DesignSystem.softFill)
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("quickEntry.date.\(title)")
    }

    var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            categorySection(title: "常用", categories: recentCategories)
            selectedCategoryRow
            allCategoriesToggle

            if showAllCategories {
                categorySection(title: "全部分类", categories: rootCategories)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .glassCard()
    }

    /// 当前选中的分类，以及一颗明确的「换小类」按钮。
    ///
    /// 点格子现在直接选中（落到上次用过的小类），小类因此需要一个看得见的入口——
    /// 只靠长按会让不知道长按的人丢掉选择具体小类的能力。
    @ViewBuilder
    private var selectedCategoryRow: some View {
        if let selectedCategory {
            let children = Category.childCategories(
                for: selectedCategory.rootCategoryName,
                in: currentCategories,
                isExpense: isExpense
            )
            HStack(spacing: 8) {
                Image(systemName: selectedCategory.icon)
                    .font(.caption2)
                    .foregroundStyle(Color(hex: selectedCategory.colorHex))
                Text("已选 \(selectedCategory.entryDisplayName)")
                    .font(DesignSystem.Typography.compactLabel)
                    .foregroundStyle(DesignSystem.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if !children.isEmpty {
                    Button {
                        showWheel(
                            for: rootCategory(for: selectedCategory.rootCategoryName, in: currentCategories) ?? selectedCategory,
                            sourceFrame: nil
                        )
                    } label: {
                        HStack(spacing: 3) {
                            Text("换小类")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .font(DesignSystem.Typography.compactLabel.weight(.semibold))
                        .foregroundStyle(DesignSystem.primaryColor)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 34)
                        .background(DesignSystem.primaryColor.opacity(0.12))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("换小类，当前 \(selectedCategory.entryDisplayName)")
                    .accessibilityIdentifier("quickEntry.changeSubcategory")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(DesignSystem.softFill)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var allCategoriesToggle: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86)) {
                    showAllCategories.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                Image(systemName: showAllCategories ? "chevron.up.circle.fill" : "square.grid.2x2")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.primaryColor)

                Text(showAllCategories ? "收起全部分类" : "展开全部分类")
                    .font(DesignSystem.Typography.compactLabel)
                    .foregroundStyle(DesignSystem.textSecondary)

                    Spacer(minLength: 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpense {
                Rectangle()
                    .fill(DesignSystem.dividerColor)
                    .frame(width: 1, height: 22)

                if dailyBudgetOverride != nil {
                    Button {
                        dailyBudgetOverride = nil
                        HapticManager.selection()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(DesignSystem.textTertiary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("恢复跟随分类")
                }

                Text(dailyBudgetOverride == nil ? "日常预算" : "本笔覆盖")
                    .font(DesignSystem.Typography.supportingLabel)
                    .foregroundStyle(dailyBudgetOverride == nil ? DesignSystem.textSecondary : DesignSystem.primaryColor)
                    .lineLimit(1)

                Toggle("计入日常预算", isOn: dailyBudgetBinding)
                    .labelsHidden()
                    .tint(DesignSystem.primaryColor)
                    .scaleEffect(0.82)
                    .frame(width: 42)
            } else if let selectedCategory {
                Text(selectedCategory.entryDisplayName)
                    .font(DesignSystem.Typography.supportingLabel)
                    .foregroundStyle(DesignSystem.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(DesignSystem.softFill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func categorySection(title: String, categories: [Category]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(DesignSystem.Typography.compactLabelEmphasized)
                .foregroundStyle(DesignSystem.textTertiary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(categories, id: \.id) { category in
                    categoryButton(category)
                }
            }
        }
    }

    private func categoryButton(_ category: Category) -> some View {
        let children = Category.childCategories(for: category.rootCategoryName, in: currentCategories, isExpense: isExpense)
        return CategorySelectionTile(
            category: category,
            selectedCategory: selectedCategory,
            hasChildren: !children.isEmpty,
            iconSize: .subheadline,
            circleSize: 36,
            minHeight: 62,
            onSelect: { _ in selectCategory(category) },
            onOpenChildren: { sourceFrame in
                showWheel(for: category, sourceFrame: sourceFrame)
            }
        )
    }

    var noteField: some View {
        HStack {
            Image(systemName: "pencil")
                .foregroundStyle(DesignSystem.textTertiary)
            TextField("添加备注...", text: $note)
                .foregroundStyle(DesignSystem.textPrimary)
                .font(.subheadline)
        }
        .padding(12)
        .background(DesignSystem.softFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var effectiveDailyBudgetValue: Bool {
        dailyBudgetOverride ?? BudgetScope.includesCategory(selectedCategory)
    }

    private var dailyBudgetBinding: Binding<Bool> {
        Binding(
            get: { effectiveDailyBudgetValue },
            set: { value in
                dailyBudgetOverride = value
                HapticManager.selection()
            }
        )
    }

    private var numberPad: some View {
        QuickEntryNumberPad(onKeyPress: handleKeyPress)
    }

    private var submitButton: some View {
        QuickEntrySubmitButton(isEnabled: canSubmitAmount, isExpense: isExpense, action: saveTransaction)
    }

    @ViewBuilder
    var bottomControls: some View {
        if #available(iOS 26.0, *) {
            LiquidGlassContainer(spacing: 4) {
                bottomControlsContent
            }
            .padding(.horizontal)
            .padding(.top, DesignSystem.space8)
            .padding(.bottom, DesignSystem.space8)
            .background(DesignSystem.surfaceBackground)
        } else {
            bottomControlsContent
                .padding(.horizontal)
                .padding(.top, DesignSystem.space8)
                .padding(.bottom, DesignSystem.space8)
                .background(DesignSystem.cardBackground)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(DesignSystem.dividerColor)
                        .frame(height: 1)
                }
        }
    }

    private var bottomControlsContent: some View {
        VStack(spacing: DesignSystem.space8) {
            if isBackdated {
                backdatedNotice
            }
            numberPad
            submitButton
        }
    }

    /// 补录状态挨着保存按钮，而不是只体现在上方那个小日期控件里。
    private var backdatedNotice: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption2.weight(.semibold))
            Text("补录到 \(selectedDate.fullDateString)，不是今天")
                .font(DesignSystem.Typography.supportingLabel)
            Spacer(minLength: 4)
            Button {
                withAnimation(reduceMotion ? nil : DesignSystem.quickAnimation) {
                    selectedDate = Calendar.current.startOfDay(for: Date())
                }
                HapticManager.selection()
            } label: {
                Text("改回今天")
                    .font(DesignSystem.Typography.supportingLabel.weight(.semibold))
                    .padding(.horizontal, 8)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(DesignSystem.warningColor)
        .padding(.horizontal, 10)
        .background(DesignSystem.warningColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("quickEntry.backdatedNotice")
    }
}
