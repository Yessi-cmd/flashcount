import SwiftUI
import SwiftData

/// 分期还款确认。
///
/// 从前「还一期」只把期数加一，分期待还随之减少，可动用资金反而上涨——
/// 还了债看起来更有钱。这里把还款补全成一次真实的资金流出。
struct InstallmentRepaymentSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(
        filter: #Predicate<Category> { $0.isExpense == true && $0.isArchived == false },
        sort: \Category.sortOrder
    ) private var expenseCategories: [Category]

    let bill: InstallmentBill

    @State private var date = Date()
    @State private var selectedCategoryID: UUID?
    @State private var recordsTransaction = true
    @State private var saveError: String?

    init(bill: InstallmentBill) {
        self.bill = bill
    }

    private var installmentNumber: Int {
        min(bill.normalizedPaidInstallments + 1, bill.normalizedInstallmentCount)
    }

    private var rootCategories: [Category] {
        Category.rootCategories(from: expenseCategories, isExpense: true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("分期账单", value: bill.name)
                    LabeledContent("本期", value: "第 \(installmentNumber) / \(bill.normalizedInstallmentCount) 期")
                    LabeledContent("剩余待还", value: bill.remainingAmount.formattedCurrency)
                }

                Section {
                    Toggle("同时记一笔支出", isOn: $recordsTransaction)
                        .accessibilityIdentifier("installment.recordsTransaction")
                } footer: {
                    Text(recordsTransaction
                         ? "还款会写入账本，可动用资金随之减少。"
                         : "仅推进期数。只有当你已经在账本里记过这笔还款时才该关闭，否则可动用资金会凭空变多。")
                }

                if recordsTransaction {
                    Section("还款") {
                        LabeledContent(
                            "金额",
                            value: InstallmentRepaymentService.suggestedAmount(for: bill).formattedCurrency
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
            .navigationTitle("还一期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("确认还款") { repay() }
                        .accessibilityIdentifier("installment.confirmRepayment")
                }
            }
            .saveErrorAlert($saveError)
        }
    }

    private func repay() {
        let amount = recordsTransaction
            ? InstallmentRepaymentService.suggestedAmount(for: bill)
            : 0

        let category = selectedCategoryID.flatMap { id in expenseCategories.first { $0.id == id } }
        do {
            try InstallmentRepaymentService(modelContext: modelContext).repayOneInstallment(
                bill,
                draft: .init(
                    amount: amount,
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
