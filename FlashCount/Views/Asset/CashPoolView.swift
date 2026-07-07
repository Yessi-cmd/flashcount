import SwiftUI
import SwiftData

struct CashPoolView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var privacyLock: PrivacyLockService
    @Query(sort: \CashPoolItem.sortOrder) private var items: [CashPoolItem]
    @Query private var states: [CashPoolState]
    @Query(sort: \InstallmentBill.createdAt, order: .reverse) private var installmentBills: [InstallmentBill]

    @State private var showAddItem = false
    @State private var editingItem: CashPoolItem?
    @State private var showCalibration = false
    @State private var calibrationText = ""
    @State private var saveError: String?
    @AppStorage("hideAssetBalance") private var hideAssetBalance = true

    private var activeItems: [CashPoolItem] {
        items.filter { !$0.isArchived }
    }

    private var manualTotal: Decimal {
        activeItems.reduce(Decimal(0)) { $0 + $1.signedAmount }
    }

    private var transactionDelta: Decimal {
        states.first?.transactionDelta ?? 0
    }

    private var activeInstallmentBills: [InstallmentBill] {
        installmentBills.filter { !$0.isArchived }
    }

    private var installmentRemainingTotal: Decimal {
        activeInstallmentBills.reduce(Decimal(0)) { $0 + $1.remainingAmount }
    }

    private var availableAmount: Decimal {
        manualTotal + transactionDelta - installmentRemainingTotal
    }

    private var hidesMoney: Bool {
        hideAssetBalance || !privacyLock.isUnlocked
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: DesignSystem.sectionSpacing) {
                        summaryCard
                        installmentSummary
                        itemList
                    }
                    .padding()
                }
            }
            .navigationTitle("资金池")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button { showCalibration = true } label: {
                            Image(systemName: "scope")
                                .foregroundStyle(DesignSystem.textSecondary)
                        }
                        Button { showAddItem = true } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(DesignSystem.primaryColor)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddItem) {
                AddCashPoolItemView(nextSortOrder: items.count)
            }
            .sheet(item: $editingItem) { item in
                AddCashPoolItemView(editItem: item, nextSortOrder: items.count)
            }
            .alert("校准资金池", isPresented: $showCalibration) {
                TextField("当前可动用资金", text: $calibrationText)
                    .keyboardType(.decimalPad)
                Button("取消", role: .cancel) { calibrationText = "" }
                Button("保存") { calibrate() }
            } message: {
                Text("输入你现在真实可动用的总资金，App 会用校准差额对齐。")
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
        VStack(spacing: 16) {
            HStack {
                Label("可动用资金", systemImage: "wallet.pass.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.textSecondary)
                Spacer()
            }

            Text(hidesMoney ? privacyLock.maskedText : availableAmount.formattedCurrency)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(availableAmount >= 0 ? DesignSystem.textPrimary : DesignSystem.expenseColor)

            HStack(spacing: 0) {
                metric(title: "资金净额", value: manualTotal)
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 30)
                metric(title: "记账变动", value: transactionDelta)
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 30)
                metric(title: "分期待还", value: -installmentRemainingTotal)
            }
        }
        .glassCard()
    }

    private func metric(title: String, value: Decimal) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(DesignSystem.textTertiary)
            Text(hidesMoney ? privacyLock.maskedText : value.formattedCurrency)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(value >= 0 ? DesignSystem.incomeColor : DesignSystem.expenseColor)
        }
        .frame(maxWidth: .infinity)
    }

    private var installmentSummary: some View {
        NavigationLink {
            InstallmentBillView()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DesignSystem.expenseColor.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "creditcard.trianglebadge.exclamationmark.fill")
                        .font(.subheadline)
                        .foregroundStyle(DesignSystem.expenseColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("分期账单")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.textPrimary)
                    Text("\(activeInstallmentBills.count) 笔正在追踪")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(hidesMoney ? privacyLock.maskedText : installmentRemainingTotal.formattedCurrency)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(DesignSystem.expenseColor)
                    Text("剩余待还")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.textTertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.textTertiary)
            }
            .glassCard()
        }
        .buttonStyle(.plain)
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("资金组成")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.textSecondary)
                Spacer()
                Text("\(activeItems.count) 项")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textTertiary)
            }

            if activeItems.isEmpty {
                emptyState
            } else {
                ForEach(activeItems, id: \.id) { item in
                    cashPoolItemRow(item)
                    if item.id != activeItems.last?.id {
                        Divider().background(DesignSystem.softFill)
                    }
                }
            }
        }
        .glassCard()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 34))
                .foregroundStyle(DesignSystem.textTertiary)
            Text("先盘点一笔可动用资金")
                .font(.subheadline)
                .foregroundStyle(DesignSystem.textSecondary)
            Button("添加资金项") {
                showAddItem = true
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(DesignSystem.primaryColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func cashPoolItemRow(_ item: CashPoolItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(item.kind.isNegative ? DesignSystem.expenseColor.opacity(0.12) : DesignSystem.incomeColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: item.kind.icon)
                    .font(.subheadline)
                    .foregroundStyle(item.kind.isNegative ? DesignSystem.expenseColor : DesignSystem.incomeColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.textPrimary)
                Text(item.kind.displayName)
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textTertiary)
            }
            Spacer()
            Text(hidesMoney ? privacyLock.maskedText : item.signedAmount.formattedCurrency)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(item.kind.isNegative ? DesignSystem.expenseColor : DesignSystem.incomeColor)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { editingItem = item }
        .contextMenu {
            Button { editingItem = item } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button(role: .destructive) {
                item.isArchived = true
                item.updatedAt = Date()
                try? modelContext.save()
            } label: {
                Label("归档", systemImage: "archivebox")
            }
        }
    }

    private func calibrate() {
        guard let target = Decimal(string: calibrationText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        CashPoolService(modelContext: modelContext).calibrate(
            to: target,
            items: activeItems,
            installmentLiability: installmentRemainingTotal
        )
        if let error = safeSave(modelContext) {
            saveError = error
        } else {
            HapticManager.success()
        }
        calibrationText = ""
    }
}

struct AddCashPoolItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var editItem: CashPoolItem?
    let nextSortOrder: Int

    @State private var name = ""
    @State private var kind: CashPoolItemKind = .cash
    @State private var amountText = ""
    @State private var note = ""
    @State private var saveError: String?

    private var isEditing: Bool { editItem != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                Form {
                    Section {
                        TextField(kind.inputPlaceholder, text: $name)
                        Picker("类型", selection: $kind) {
                            ForEach(CashPoolItemKind.allCases) { item in
                                Label(item.displayName, systemImage: item.icon).tag(item)
                            }
                        }
                        TextField("金额", text: $amountText)
                            .keyboardType(.decimalPad)
                        TextField("备注", text: $note)
                    } header: {
                        Text("资金项")
                    } footer: {
                        if kind == .liability {
                            Text("有固定期数和每月还款日的分期，请到“分期账单”里记录；这里适合记录信用卡待还、朋友借款等其他待还款。")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(isEditing ? "编辑资金项" : "添加资金项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || amountText.isEmpty)
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
        guard let editItem, name.isEmpty else { return }
        name = editItem.name
        kind = editItem.kind
        amountText = NSDecimalNumber(decimal: editItem.amount).stringValue
        note = editItem.note
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = Decimal(string: amountText), amount >= 0, !cleanName.isEmpty else { return }

        if let editItem {
            editItem.name = cleanName
            editItem.kind = kind
            editItem.amount = amount
            editItem.note = note
            editItem.updatedAt = Date()
        } else {
            modelContext.insert(CashPoolItem(name: cleanName, kind: kind, amount: amount, note: note, sortOrder: nextSortOrder))
        }

        if let error = safeSave(modelContext) {
            saveError = error
        } else {
            dismiss()
        }
    }
}
