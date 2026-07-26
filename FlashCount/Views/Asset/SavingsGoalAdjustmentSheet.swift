import SwiftUI
import SwiftData

/// 储蓄目标的存入 / 取出。
/// 以前要记一次存钱，得打开编辑表单把「当前已存」整个数字重打一遍。
struct SavingsGoalAdjustmentSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let goal: SavingsGoal

    @State private var isDeposit = true
    @State private var amountText = ""
    @State private var amountError: MoneyValidationError?
    @State private var saveError: String?
    @FocusState private var amountFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("方式", selection: $isDeposit) {
                        Text("存入").tag(true)
                        Text("取出").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("savingsGoal.adjustmentMode")
                }

                Section {
                    HStack {
                        Text("金额")
                        Spacer()
                        TextField("金额", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($amountFocused)
                            .onChange(of: amountText) { _, _ in amountError = nil }
                            .accessibilityIdentifier("savingsGoal.adjustmentAmount")
                    }
                    ValidationMessage(message: amountError?.errorDescription)
                } footer: {
                    Text("存入只调整目标进度，不会记入账本——这笔钱只是从可动用挪到已存，并没有花掉。")
                }

                Section {
                    LabeledContent("当前已存", value: goal.currentAmount.formattedCurrency)
                    LabeledContent("目标", value: goal.targetAmount.formattedCurrency)
                    LabeledContent("还差", value: goal.remainingAmount.formattedCurrency)
                }
            }
            .navigationTitle(goal.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { apply() }
                        .accessibilityIdentifier("savingsGoal.confirmAdjustment")
                }
            }
            .saveErrorAlert($saveError)
            .onAppear { amountFocused = true }
        }
    }

    private func apply() {
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

        do {
            let service = SavingsGoalService(modelContext: modelContext)
            if isDeposit {
                try service.deposit(amount, into: goal)
            } else {
                try service.withdraw(amount, from: goal)
            }
            HapticManager.success()
            dismiss()
        } catch {
            saveError = error.localizedDescription
            HapticManager.error()
        }
    }
}
