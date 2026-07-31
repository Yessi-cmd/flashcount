import SwiftUI
import SwiftData

/// 订阅追踪列表与续费确认。
///
/// 订阅是提醒优先的义务，**绝不自动生成交易**；「已续费」通过
/// `SubscriptionService.advanceRenewal` 推进日期并默认写一笔支出——否则
/// 释放义务看起来像多出钱（与分期账单同一条不变量）。所有变更后都会
/// 刷新通知排期，因为重排是「清空重建」，漏一次就会把订阅提醒整个清掉。
struct SubscriptionView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var privacyLock: PrivacyLockService
    @Query(sort: \Subscription.createdAt, order: .reverse) private var subscriptions: [Subscription]

    /// 续费通知点按带进来的订阅 id。当前只用于把用户带到正确的页面，
    /// 具体某条的定位留给后续（先保证「点开看到的正是订阅页」）。
    let initialSubscriptionID: UUID?

    @State private var showAddSubscription = false
    @State private var editingSubscription: Subscription?
    @State private var renewingSubscription: Subscription?
    @State private var saveError: String?

    init(initialSubscriptionID: UUID? = nil) {
        self.initialSubscriptionID = initialSubscriptionID
    }

    private var activeSubscriptions: [Subscription] {
        subscriptions.filter { !$0.isArchived }
    }

    private var aggregation: SubscriptionAggregation {
        SubscriptionAggregation(subscriptions: activeSubscriptions)
    }

    private var hidesMoney: Bool {
        PrivacyVisibilityPolicy.hidesAssets(isUnlocked: privacyLock.isUnlocked)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        summaryCard
                        if activeSubscriptions.isEmpty {
                            emptyState
                        } else {
                            ForEach(activeSubscriptions, id: \.id) { subscription in
                                subscriptionCard(subscription)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("订阅追踪")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    PrivacyVisibilityButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSubscription = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(DesignSystem.primaryColor)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("添加订阅")
                    .accessibilityIdentifier("subscription.add")
                }
            }
            .sheet(isPresented: $showAddSubscription) {
                AddSubscriptionView()
            }
            .sheet(item: $renewingSubscription) { subscription in
                SubscriptionRenewalSheet(subscription: subscription)
            }
            .sheet(item: $editingSubscription) { subscription in
                AddSubscriptionView(editSubscription: subscription)
            }
            .alert("保存失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好的") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("订阅合计", systemImage: "repeat.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
                Spacer()
                Text("\(aggregation.count) 项")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DesignSystem.primaryColor)
            }

            Text(hidesMoney ? privacyLock.maskedText : aggregation.monthlyTotal.formattedCurrency)
                .font(DesignSystem.Typography.amount)
                .monospacedDigit()
                .foregroundStyle(DesignSystem.primaryColor)
            Text(hidesMoney ? " " : "每月合计")
                .font(.caption2)
                .foregroundStyle(DesignSystem.textTertiary)

            HStack(spacing: 0) {
                metric(title: "每年", value: hidesMoney ? privacyLock.maskedText : aggregation.yearlyTotal.formattedCurrency)
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 30)
                metric(title: "最近续费", value: aggregation.nextRenewalDate?.shortDateString ?? "无")
            }
        }
        .glassCard()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "repeat.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(DesignSystem.textTertiary)
            Text("暂无订阅")
                .font(.headline)
                .foregroundStyle(DesignSystem.textSecondary)
            Text("记录月度、季度、年度的订阅与续费提醒")
                .font(.subheadline)
                .foregroundStyle(DesignSystem.textTertiary)
            Button("添加订阅") {
                showAddSubscription = true
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .background(DesignSystem.primaryColor)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func subscriptionCard(_ subscription: Subscription) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                revealOrPerform { editingSubscription = subscription }
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(subscription.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DesignSystem.textPrimary)
                            Text(nextDueText(for: subscription))
                                .font(.caption)
                                .foregroundStyle(nextDueColor(for: subscription))
                        }
                        Spacer()
                        Text(hidesMoney ? privacyLock.maskedText : subscription.cost.formattedCurrency)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(DesignSystem.primaryColor)
                    }

                    HStack(spacing: 0) {
                        cardMetric(title: "周期", value: subscription.billingCycle.displayName)
                        Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 28)
                        cardMetric(title: "提前提醒", value: remindText(for: subscription))
                        Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 28)
                        cardMetric(title: "下次续费", value: subscription.nextRenewalDate.shortDateString)
                    }

                    if !subscription.note.isEmpty {
                        Text(subscription.note)
                            .font(.caption)
                            .foregroundStyle(DesignSystem.textTertiary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hidesMoney ? "订阅，验证后编辑" : "编辑订阅\(subscription.name)")
            .accessibilityHint("双击编辑")

            HStack {
                Spacer()
                Button {
                    revealOrPerform { renewingSubscription = subscription }
                } label: {
                    Label("已续费", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityHint("确认续费并记账")
                .accessibilityIdentifier("subscription.renew")
            }
        }
        .glassCard()
        .contextMenu {
            Button { revealOrPerform { editingSubscription = subscription } } label: {
                Label(hidesMoney ? "验证后编辑" : "编辑", systemImage: hidesMoney ? "lock.open" : "pencil")
            }
            Button {
                revealOrPerform { renewingSubscription = subscription }
            } label: {
                Label("已续费", systemImage: "checkmark.circle")
            }
            Button(role: .destructive) {
                do {
                    try SubscriptionService(modelContext: modelContext).archive(subscription)
                    refreshNotifications()
                } catch {
                    saveError = error.localizedDescription
                }
            } label: {
                Label("归档", systemImage: "archivebox")
            }
        }
    }

    private func remindText(for subscription: Subscription) -> String {
        guard let days = subscription.remindBeforeDays, days > 0 else { return "不提醒" }
        return "提前 \(days) 天"
    }

    private func nextDueText(for subscription: Subscription) -> String {
        if subscription.isOverdue() {
            return "已到期 \(subscription.nextRenewalDate.shortDateString)"
        }
        return "下次续费 \(subscription.nextRenewalDate.shortDateString)"
    }

    private func nextDueColor(for subscription: Subscription) -> Color {
        subscription.isOverdue() ? DesignSystem.expenseColor : DesignSystem.textTertiary
    }

    private func revealOrPerform(_ action: () -> Void) {
        guard privacyLock.isUnlocked else {
            privacyLock.requestReveal()
            return
        }
        action()
    }

    private func metric(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(DesignSystem.textTertiary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(DesignSystem.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
    }

    private func cardMetric(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(DesignSystem.textTertiary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(DesignSystem.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
    }

    /// 重排通知。快照已在 service 写路径里更新，这里只需带上提醒数据重建一次。
    private func refreshNotifications() {
        let reminders = (try? ReminderDataService(modelContext: modelContext).load()) ?? []
        Task {
            try? await NotificationScheduleCoordinator.shared.rebuild(reminders: reminders)
        }
    }
}

private struct AddSubscriptionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var editSubscription: Subscription?

    @State private var name = ""
    @State private var costText = ""
    @State private var costError: MoneyValidationError?
    @State private var billingCycle: SubscriptionBillingCycle = .monthly
    @State private var nextRenewalDate = Date()
    @State private var remindBeforeDays = 0
    @State private var note = ""
    @State private var saveError: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case cost
    }

    private var isEditing: Bool { editSubscription != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                Form {
                    Section("订阅") {
                        TextField("名称，例如：iCloud", text: $name)
                        TextField("单期金额", text: $costText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .cost)
                            .onChange(of: costText) { _, _ in costError = nil }
                        ValidationMessage(message: costError?.errorDescription)
                    }

                    Section("计费") {
                        Picker("计费周期", selection: $billingCycle) {
                            ForEach(SubscriptionBillingCycle.allCases, id: \.self) { cycle in
                                Text(cycle.displayName).tag(cycle)
                            }
                        }
                        DatePicker("下次续费", selection: $nextRenewalDate, displayedComponents: .date)
                        Stepper("提前 \(remindBeforeDays) 天提醒", value: $remindBeforeDays, in: 0...90)
                    }

                    Section("备注") {
                        TextField("备注", text: $note)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(isEditing ? "编辑订阅" : "添加订阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || costText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: load)
            .alert("保存失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好的") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func load() {
        guard let editSubscription, name.isEmpty else { return }
        name = editSubscription.name
        costText = NSDecimalNumber(decimal: editSubscription.cost).stringValue
        billingCycle = editSubscription.billingCycle
        nextRenewalDate = editSubscription.nextRenewalDate
        remindBeforeDays = editSubscription.remindBeforeDays ?? 0
        note = editSubscription.note
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        let cost: Decimal
        switch MoneyValidation.parse(costText, requirement: .positive) {
        case .success(let value):
            cost = value
            costError = nil
        case .failure(let error):
            costError = error
            focusedField = .cost
            HapticManager.error()
            return
        }

        let draft = SubscriptionService.Draft(
            name: cleanName,
            cost: cost,
            billingCycle: billingCycle,
            nextRenewalDate: nextRenewalDate,
            remindBeforeDays: remindBeforeDays == 0 ? nil : remindBeforeDays,
            note: note
        )

        do {
            let service = SubscriptionService(modelContext: modelContext)
            if let editSubscription {
                try service.update(editSubscription, draft: draft)
            } else {
                try service.add(draft)
            }
            dismiss()
        } catch {
            saveError = error.localizedDescription
            HapticManager.error()
        }
    }
}

/// 续费确认。与分期还款同一条钱不变量：释放义务必须写支出，否则
/// 可动用资金会凭空上涨；只有用户已手动记过这笔支出时才应关闭。
private struct SubscriptionRenewalSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(
        filter: #Predicate<Category> { $0.isExpense == true && $0.isArchived == false },
        sort: \Category.sortOrder
    ) private var expenseCategories: [Category]

    let subscription: Subscription

    @State private var date = Date()
    @State private var selectedCategoryID: UUID?
    @State private var recordsTransaction = true
    @State private var saveError: String?

    private var rootCategories: [Category] {
        Category.rootCategories(from: expenseCategories, isExpense: true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("订阅", value: subscription.name)
                    LabeledContent("本次续费金额", value: subscription.cost.formattedCurrency)
                    LabeledContent("下次续费", value: subscription.nextRenewalDate.shortDateString)
                }

                Section {
                    Toggle("同时记一笔支出", isOn: $recordsTransaction)
                        .accessibilityIdentifier("subscription.recordsTransaction")
                } footer: {
                    Text(recordsTransaction
                         ? "续费会写入账本，可动用资金随之减少。"
                         : "仅推进下次续费日期。只有当你已经在账本里记过这笔支出时才该关闭，否则可动用资金会凭空变多。")
                }

                if recordsTransaction {
                    Section("支出") {
                        LabeledContent(
                            "金额",
                            value: subscription.cost.formattedCurrency
                        )

                        DatePicker("日期", selection: $date, displayedComponents: .date)

                        Picker("分类", selection: $selectedCategoryID) {
                            Text("不分类").tag(UUID?.none)
                            ForEach(rootCategories, id: \.id) { category in
                                Text(category.name).tag(UUID?.some(category.id))
                            }
                        }
                    }
                }
            }
            .navigationTitle("已续费")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("确认续费") { confirm() }
                        .accessibilityIdentifier("subscription.confirmRenewal")
                }
            }
            .saveErrorAlert($saveError)
        }
    }

    private func confirm() {
        let category = selectedCategoryID.flatMap { id in expenseCategories.first { $0.id == id } }
        do {
            try SubscriptionService(modelContext: modelContext).advanceRenewal(
                subscription,
                draft: .init(
                    date: date,
                    category: category,
                    recordsTransaction: recordsTransaction
                )
            )
            HapticManager.success()
            dismiss()
        } catch {
            saveError = error.localizedDescription
            HapticManager.error()
        }
    }
}
