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
        VStack(spacing: 3) {
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

            ValidationMessage(message: amountError?.errorDescription)

            // 日期选择器 - 始终可见，方便补录历史账单
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.textSecondary)
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .scaleEffect(0.8)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            categorySection(title: "常用", categories: recentCategories)
            allCategoriesToggle

            if showAllCategories {
                categorySection(title: "全部分类", categories: rootCategories)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .glassCard()
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
            numberPad
            submitButton
        }
    }

    var successOverlay: some View {
        VStack(spacing: 16) {
            if reduceMotion {
                Image(systemName: "checkmark.circle.fill")
                    .font(DesignSystem.Typography.amount)
                    .foregroundStyle(DesignSystem.incomeColor)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(DesignSystem.Typography.amount)
                    .foregroundStyle(DesignSystem.incomeColor)
                    .symbolEffect(.bounce, value: showSuccess)
            }

            Text("记账成功！")
                .font(.headline)
                .foregroundStyle(DesignSystem.textPrimary)
                .accessibilityFocused($successOverlayFocused)

            if let budgetReminderText {
                HStack(spacing: 6) {
                    Image(systemName: budgetReminderIcon)
                    Text(budgetReminderText)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(budgetReminderColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(budgetReminderColor.opacity(0.12))
                .clipShape(Capsule())
            }

            Divider()
                .frame(width: 160)

            Button {
                resetForm()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("再记一笔")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.primaryColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DesignSystem.primaryColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)

            Button {
                dismiss()
            } label: {
                Text("完成")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.textSecondary)
                    .underline()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.surfaceBackground.opacity(0.98))
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    var budgetReminderIcon: String {
        switch budgetReminderLevel {
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "flame.fill"
        default: return "checkmark.circle.fill"
        }
    }

    var budgetReminderColor: Color {
        switch budgetReminderLevel {
        case .warning: return DesignSystem.warningColor
        case .danger: return DesignSystem.dangerColor
        default: return DesignSystem.incomeColor
        }
    }
}
