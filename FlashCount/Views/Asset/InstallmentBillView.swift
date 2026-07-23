import SwiftUI
import SwiftData

struct InstallmentBillView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var privacyLock: PrivacyLockService
    @Query(sort: \InstallmentBill.createdAt, order: .reverse) private var bills: [InstallmentBill]

    @State private var showAddBill = false
    @State private var editingBill: InstallmentBill?
    @State private var saveError: String?

    private var activeBills: [InstallmentBill] {
        bills.filter { !$0.isArchived }
    }

    private var remainingTotal: Decimal {
        activeBills.reduce(Decimal(0)) { $0 + $1.remainingAmount }
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
                        if activeBills.isEmpty {
                            emptyState
                        } else {
                            ForEach(activeBills, id: \.id) { bill in
                                billCard(bill)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("分期账单")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    PrivacyVisibilityButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddBill = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(DesignSystem.primaryColor)
                    }
                }
            }
            .sheet(isPresented: $showAddBill) {
                AddInstallmentBillView()
            }
            .sheet(item: $editingBill) { bill in
                AddInstallmentBillView(editBill: bill)
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
                Label("剩余待还", systemImage: "creditcard.trianglebadge.exclamationmark.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
                Spacer()
                Text("\(activeBills.count) 笔")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DesignSystem.primaryColor)
            }

            Text(hidesMoney ? privacyLock.maskedText : remainingTotal.formattedCurrency)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DesignSystem.expenseColor)

            HStack(spacing: 0) {
                textMetric(title: "待还期数", value: "\(activeBills.reduce(0) { $0 + $1.remainingInstallments }) 期")
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 30)
                textMetric(title: "最近还款", value: nearestDueText)
            }
        }
        .glassCard()
    }

    private var nearestDueText: String {
        let nearest = activeBills.compactMap { $0.nextRepaymentDate() }.min()
        return nearest?.shortDateString ?? "无"
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "creditcard.trianglebadge.exclamationmark.fill")
                .font(.system(size: 48))
                .foregroundStyle(DesignSystem.textTertiary)
            Text("暂无分期账单")
                .font(.headline)
                .foregroundStyle(DesignSystem.textSecondary)
            Text("记录每笔分期的金额、期数和还款日")
                .font(.subheadline)
                .foregroundStyle(DesignSystem.textTertiary)
            Button("添加分期") {
                showAddBill = true
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

    private func billCard(_ bill: InstallmentBill) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bill.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.textPrimary)
                    Text(nextDueText(for: bill))
                        .font(.caption)
                        .foregroundStyle(nextDueColor(for: bill))
                }
                Spacer()
                Text(hidesMoney ? privacyLock.maskedText : bill.remainingAmount.formattedCurrency)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(DesignSystem.expenseColor)
            }

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 5)
                    .fill(DesignSystem.dividerColor)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(DesignSystem.expenseColor.opacity(0.75))
                            .frame(width: hidesMoney ? 0 : geo.size.width * CGFloat(bill.progress))
                    }
            }
            .frame(height: 10)

            HStack(spacing: 0) {
                billMetric(title: "每期", value: hidesMoney ? privacyLock.maskedText : bill.installmentAmount.formattedCurrency)
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 28)
                billMetric(title: "进度", value: hidesMoney ? privacyLock.maskedText : "\(bill.normalizedPaidInstallments)/\(bill.normalizedInstallmentCount) 期")
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 28)
                billMetric(title: "还款日", value: "每月 \(bill.repaymentDay) 日")
            }

            HStack {
                if !bill.note.isEmpty {
                    Text(bill.note)
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textTertiary)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    markOneInstallmentPaid(bill)
                } label: {
                    Label("还一期", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                }
                .disabled(bill.isCompleted)
            }
        }
        .glassCard()
        .contentShape(Rectangle())
        .onTapGesture { revealOrPerform { editingBill = bill } }
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            Button { revealOrPerform { editingBill = bill } } label: {
                Label(hidesMoney ? "验证后编辑" : "编辑", systemImage: hidesMoney ? "lock.open" : "pencil")
            }
            Button {
                markOneInstallmentPaid(bill)
            } label: {
                Label("还一期", systemImage: "checkmark.circle")
            }
            .disabled(bill.isCompleted)
            Button(role: .destructive) {
                bill.isArchived = true
                bill.updatedAt = Date()
                if let error = safeSave(modelContext) {
                    saveError = error
                }
            } label: {
                Label("归档", systemImage: "archivebox")
            }
        }
        .opacity(bill.isCompleted ? 0.68 : 1)
    }

    private func revealOrPerform(_ action: () -> Void) {
        guard privacyLock.isUnlocked else {
            privacyLock.requestReveal()
            return
        }
        action()
    }

    private func billMetric(title: String, value: String) -> some View {
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

    private func textMetric(title: String, value: String) -> some View {
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

    private func nextDueText(for bill: InstallmentBill) -> String {
        guard let date = bill.nextRepaymentDate() else { return "已还清" }
        let today = Calendar.current.startOfDay(for: Date())
        if date < today {
            return "已到期 \(date.shortDateString)"
        }
        return "下次还款 \(date.shortDateString)"
    }

    private func nextDueColor(for bill: InstallmentBill) -> Color {
        guard let date = bill.nextRepaymentDate() else { return DesignSystem.incomeColor }
        return date < Calendar.current.startOfDay(for: Date()) ? DesignSystem.expenseColor : DesignSystem.textTertiary
    }

    private func markOneInstallmentPaid(_ bill: InstallmentBill) {
        guard !bill.isCompleted else { return }
        bill.paidInstallments = min(bill.normalizedPaidInstallments + 1, bill.normalizedInstallmentCount)
        bill.updatedAt = Date()
        if let error = safeSave(modelContext) {
            saveError = error
        } else {
            HapticManager.success()
        }
    }
}

private struct AddInstallmentBillView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var editBill: InstallmentBill?

    @State private var name = ""
    @State private var totalAmountText = ""
    @State private var installmentCount = 12
    @State private var paidInstallments = 0
    @State private var firstRepaymentDate = Date()
    @State private var repaymentDay = Calendar.current.component(.day, from: Date())
    @State private var note = ""
    @State private var saveError: String?

    private var isEditing: Bool { editBill != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                Form {
                    Section("账单") {
                        TextField("名称，例如：手机分期", text: $name)
                        TextField("总金额", text: $totalAmountText)
                            .keyboardType(.decimalPad)
                    }

                    Section("分期") {
                        Stepper("分期数 \(installmentCount) 期", value: $installmentCount, in: 1...120)
                        Stepper("已还 \(paidInstallments) 期", value: $paidInstallments, in: 0...installmentCount)
                        DatePicker("首期还款日", selection: $firstRepaymentDate, displayedComponents: .date)
                        Stepper("每月还款日 \(repaymentDay) 日", value: $repaymentDay, in: 1...31)
                    }

                    Section("备注") {
                        TextField("备注", text: $note)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(isEditing ? "编辑分期" : "添加分期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || totalAmountText.isEmpty)
                }
            }
            .onAppear(perform: load)
            .onChange(of: installmentCount) { _, newValue in
                paidInstallments = min(paidInstallments, newValue)
            }
            .onChange(of: firstRepaymentDate) { _, newValue in
                repaymentDay = Calendar.current.component(.day, from: newValue)
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

    private func load() {
        guard let editBill, name.isEmpty else { return }
        name = editBill.name
        totalAmountText = NSDecimalNumber(decimal: editBill.totalAmount).stringValue
        installmentCount = editBill.normalizedInstallmentCount
        paidInstallments = editBill.normalizedPaidInstallments
        firstRepaymentDate = editBill.firstRepaymentDate
        repaymentDay = editBill.repaymentDay
        note = editBill.note
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let totalAmount = Decimal(string: totalAmountText), totalAmount > 0, !cleanName.isEmpty else { return }
        let cleanInstallmentCount = max(installmentCount, 1)
        let cleanPaidInstallments = min(max(paidInstallments, 0), cleanInstallmentCount)
        let cleanRepaymentDay = min(max(repaymentDay, 1), 31)

        if let editBill {
            editBill.name = cleanName
            editBill.totalAmount = totalAmount
            editBill.installmentCount = cleanInstallmentCount
            editBill.paidInstallments = cleanPaidInstallments
            editBill.firstRepaymentDate = firstRepaymentDate
            editBill.repaymentDay = cleanRepaymentDay
            editBill.note = note
            editBill.updatedAt = Date()
        } else {
            modelContext.insert(InstallmentBill(
                name: cleanName,
                totalAmount: totalAmount,
                installmentCount: cleanInstallmentCount,
                paidInstallments: cleanPaidInstallments,
                repaymentDay: cleanRepaymentDay,
                firstRepaymentDate: firstRepaymentDate,
                note: note
            ))
        }

        if let error = safeSave(modelContext) {
            saveError = error
        } else {
            dismiss()
        }
    }
}
