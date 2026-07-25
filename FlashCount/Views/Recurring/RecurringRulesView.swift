import SwiftUI
import SwiftData

/// 周期性规则管理页面
struct RecurringRulesView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var privacyLock: PrivacyLockService
    @Query(sort: \RecurringRule.createdAt, order: .reverse) private var rules: [RecurringRule]
    @Query private var occurrences: [RecurringOccurrence]
    @Query(filter: #Predicate<Transaction> { $0.isExpense == true }, sort: \Transaction.date) private var expenseTransactions: [Transaction]
    @State private var showAddRule = false
    @State private var showBackfill = false
    @State private var editingRule: RecurringRule?
    @State private var suggestionToCreate: RecurringSuggestion?
    @State private var rulePendingDeletion: RecurringRule?
    @State private var saveError: String?
    @State private var dismissedSuggestionFingerprints: Set<String> = []
    @State private var cachedSuggestions: [RecurringSuggestion] = []
    @State private var cachedPendingBackfill: [RecurringOccurrencePreview] = []

    private let suggestionDismissalStore = UserDefaultsRecurringSuggestionDismissalStore()

    private var pendingCashDelta: Decimal {
        cachedPendingBackfill.reduce(Decimal.zero) { $0 + $1.signedAmount }
    }

    private var suggestionDigest: Int {
        var hasher = Hasher()
        for transaction in expenseTransactions {
            hasher.combine(transaction.id)
            hasher.combine(transaction.amount)
            hasher.combine(transaction.date)
            hasher.combine(transaction.note)
            hasher.combine(transaction.category?.id)
            hasher.combine(transaction.category?.name)
            hasher.combine(transaction.category?.isArchived)
            hasher.combine(transaction.ledger?.id)
            hasher.combine(transaction.recurringRule?.id)
        }
        for rule in rules {
            hasher.combine(rule.id)
            hasher.combine(rule.amount)
            hasher.combine(rule.isExpense)
            hasher.combine(rule.frequency)
            hasher.combine(rule.title)
            hasher.combine(rule.note)
            hasher.combine(rule.nextDueDate)
            hasher.combine(rule.isActive)
            hasher.combine(rule.category?.id)
            hasher.combine(rule.category?.name)
            hasher.combine(rule.ledger?.id)
        }
        for occurrence in occurrences {
            hasher.combine(occurrence.id)
            hasher.combine(occurrence.status)
            hasher.combine(occurrence.scheduledDate)
        }
        for fingerprint in dismissedSuggestionFingerprints.sorted() {
            hasher.combine(fingerprint)
        }
        return hasher.finalize()
    }

    var body: some View {
        let suggestions = cachedSuggestions
        let pendingBackfill = cachedPendingBackfill
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        if !pendingBackfill.isEmpty {
                            backfillCard
                        }
                        if !suggestions.isEmpty {
                            suggestionSection(suggestions: suggestions)
                        }
                        if rules.isEmpty {
                            emptyState
                        } else {
                            ForEach(rules, id: \.id) { rule in
                                ruleCard(rule)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("周期账单")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    PrivacyVisibilityButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddRule = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(DesignSystem.primaryColor)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("添加周期账单")
                    .accessibilityIdentifier("recurringRules.add")
                }
            }
            .sheet(isPresented: $showAddRule) { AddRecurringRuleView() }
            .sheet(isPresented: $showBackfill) {
                RecurringBackfillView(previews: pendingBackfill)
            }
            .sheet(item: $suggestionToCreate) { suggestion in
                AddRecurringRuleView(suggestion: suggestion)
            }
            .sheet(isPresented: Binding(
                get: { editingRule != nil },
                set: { if !$0 { editingRule = nil } }
            )) {
                if let editingRule {
                    AddRecurringRuleView(editRule: editingRule)
                }
            }
            .confirmationDialog("删除周期账单？", isPresented: Binding(
                get: { rulePendingDeletion != nil },
                set: { if !$0 { rulePendingDeletion = nil } }
            ), titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if let rule = rulePendingDeletion {
                        delete(rule)
                    }
                    rulePendingDeletion = nil
                }
                Button("取消", role: .cancel) {
                    rulePendingDeletion = nil
                }
            } message: {
                Text("只删除这条自动入账规则，已经生成的交易记录会保留。")
            }
            .alert("保存失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好的") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .onAppear {
                dismissedSuggestionFingerprints = suggestionDismissalStore.load()
            }
            .task(id: suggestionDigest) {
                await refreshCachedAnalysis()
            }
        }
    }

    @MainActor
    private func refreshCachedAnalysis() async {
        do {
            cachedPendingBackfill = RecurringOccurrenceService(modelContext: modelContext).pendingOccurrences(
                rules: rules,
                occurrences: occurrences,
                maxOccurrences: 120
            )
            let input = try await RecurringSuggestionDataStore(modelContainer: modelContext.container).makeInput()
            try Task.checkCancellation()
            cachedSuggestions = await RecurringSuggestionWorker().calculate(
                input: input,
                dismissedFingerprints: dismissedSuggestionFingerprints
            )
        } catch is CancellationError {
            return
        } catch {
            saveError = error.localizedDescription
        }
    }

    private var backfillCard: some View {
        Button {
            showBackfill = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(DesignSystem.warningColor.opacity(0.14))
                        .frame(width: 42, height: 42)
                    Image(systemName: "clock.badge.exclamationmark.fill")
                        .foregroundStyle(DesignSystem.warningColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("有 \(cachedPendingBackfill.count) 笔周期账待补")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.textPrimary)
                    Text("确认后才会写入账本 · 预计现金变化 \(privacyLock.isUnlocked ? pendingCashDelta.formattedCurrency : privacyLock.maskedText)")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.textTertiary)
            }
            .glassCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看待补周期账")
    }

    private func suggestionSection(suggestions: [RecurringSuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(DesignSystem.primaryColor)
                Text("发现可能的周期支出")
                    .font(.headline)
                    .foregroundStyle(DesignSystem.textPrimary)
                Spacer()
                Text("仅本机分析")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.textTertiary)
            }

            ForEach(Array(suggestions.prefix(8))) { suggestion in
                suggestionCard(suggestion)
            }
        }
    }

    private func suggestionCard(_ suggestion: RecurringSuggestion) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(DesignSystem.primaryColor.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: "repeat.circle.fill")
                    .foregroundStyle(DesignSystem.primaryColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
                    .lineLimit(1)
                Text("\(suggestion.frequency.rawValue) · 已出现 \(suggestion.occurrenceCount) 次 · 下次 \(suggestion.nextDueDate.shortDateString)")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textTertiary)
                    .lineLimit(1)
                Text(suggestion.amount.formattedCurrency)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(DesignSystem.expenseColor)
            }

            Spacer(minLength: 8)

            VStack(spacing: 8) {
                Button("创建规则") {
                    suggestionToCreate = suggestion
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.primaryColor)

                Button("忽略") {
                    dismiss(suggestion)
                }
                .font(.caption)
                .foregroundStyle(DesignSystem.textTertiary)
                .buttonStyle(.plain)
            }
        }
        .glassCard()
    }

    private func ruleCard(_ rule: RecurringRule) -> some View {
        let hidesIncome = PrivacyVisibilityPolicy.hidesIncome(
            isExpense: rule.isExpense,
            isUnlocked: privacyLock.isUnlocked
        )
        let hidesPrivateIncome = PrivacyVisibilityPolicy.hidesProtectedMetadata(
            isProtectedIncome: rule.isProtectedIncome,
            isUnlocked: privacyLock.isUnlocked
        )
        return HStack(spacing: 12) {
            Button {
                if hidesIncome {
                    privacyLock.requestReveal()
                } else {
                    editingRule = rule
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill((hidesPrivateIncome ? DesignSystem.textTertiary : Color(hex: rule.category?.colorHex ?? "#667EEA")).opacity(0.15)).frame(width: 44, height: 44)
                        Image(systemName: hidesPrivateIncome ? "lock.fill" : rule.category?.icon ?? "repeat").font(.title3)
                            .foregroundStyle(hidesPrivateIncome ? DesignSystem.textTertiary : Color(hex: rule.category?.colorHex ?? "#667EEA"))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(hidesPrivateIncome ? "隐私收入" : rule.title).font(.subheadline.weight(.medium)).foregroundStyle(DesignSystem.textPrimary)
                            if !rule.isActive {
                                Text("已暂停").font(.caption2).foregroundStyle(DesignSystem.textTertiary)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(DesignSystem.softFill).clipShape(Capsule())
                            }
                        }
                        Text("\(rule.frequency.rawValue) · 下次: \(rule.nextDueDate.shortDateString)")
                            .font(.caption).foregroundStyle(DesignSystem.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hidesIncome ? "隐私收入，验证后查看" : "编辑周期账单")
            .accessibilityHint("双击打开周期账单编辑")
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(rule.amount.formattedCurrency)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(rule.isExpense ? DesignSystem.expenseColor : DesignSystem.incomeColor)
                    .privacySensitive(hidesIncome)
                    .opacity(hidesIncome ? 0 : 1)
                    .overlay {
                        if hidesIncome {
                            Text(privacyLock.maskedText)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(DesignSystem.textTertiary)
                        }
                    }
                HStack(spacing: 8) {
                    Button {
                        toggle(rule)
                    } label: {
                        Image(systemName: rule.isActive ? "pause.circle" : "play.circle")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.textTertiary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(rule.isActive ? "暂停周期账单" : "恢复周期账单")

                    Menu {
                        Button {
                            skipNext(rule)
                        } label: {
                            Label("跳过本期", systemImage: "forward.end")
                        }
                        Button {
                            if hidesIncome {
                                privacyLock.requestReveal()
                            } else {
                                editingRule = rule
                            }
                        } label: {
                            Label(hidesIncome ? "验证后查看" : "编辑", systemImage: hidesIncome ? "lock.open" : "pencil")
                        }
                        Button(role: .destructive) {
                            rulePendingDeletion = rule
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.textTertiary)
                            .frame(width: 44, height: 44)
                    }
                }
            }
        }
        .glassCard()
        .opacity(rule.isActive ? 1 : 0.6)
        .contextMenu {
            Button {
                if hidesIncome {
                    privacyLock.requestReveal()
                } else {
                    editingRule = rule
                }
            } label: {
                Label(hidesIncome ? "验证后查看" : "编辑", systemImage: hidesIncome ? "lock.open" : "pencil")
            }
            Button {
                toggle(rule)
            } label: {
                Label(rule.isActive ? "暂停" : "恢复", systemImage: rule.isActive ? "pause.circle" : "play.circle")
            }
            Button(role: .destructive) {
                rulePendingDeletion = rule
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func skipNext(_ rule: RecurringRule) {
        guard let nextDate = rule.frequency.nextDate(from: rule.nextDueDate, anchorDay: rule.anchorDay) else {
            rule.isActive = false
            if let error = safeSave(modelContext) { saveError = error }
            return
        }
        rule.nextDueDate = nextDate
        if let endDate = rule.endDate, nextDate > endDate { rule.isActive = false }
        if let error = safeSave(modelContext) { saveError = error }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "repeat").font(.system(size: 50)).foregroundStyle(DesignSystem.textTertiary)
            Text("暂无周期账单").font(.headline).foregroundStyle(DesignSystem.textSecondary)
            Text("添加房租、话费、会员等固定服务，自动生成记录").font(.subheadline).foregroundStyle(DesignSystem.textTertiary).multilineTextAlignment(.center)
            Button { showAddRule = true } label: {
                Text("添加周期账单").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(DesignSystem.primaryColor)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        }.padding(.vertical, 60)
    }

    private func toggle(_ rule: RecurringRule) {
        rule.isActive.toggle()
        persist()
    }

    private func delete(_ rule: RecurringRule) {
        modelContext.delete(rule)
        persist()
    }

    private func dismiss(_ suggestion: RecurringSuggestion) {
        suggestionDismissalStore.dismiss(suggestion.fingerprint)
        dismissedSuggestionFingerprints.insert(suggestion.fingerprint)
        HapticManager.selection()
    }

    private func persist() {
        if let error = safeSave(modelContext) {
            saveError = error
            HapticManager.error()
        }
    }
}
