import SwiftUI
import SwiftData

// MARK: - 保存错误处理

/// 安全保存，失败时记录错误信息
@MainActor
func safeSave(_ context: ModelContext) -> String? {
    do {
        try context.save()
        return nil
    } catch {
        return error.localizedDescription
    }
}

/// 保存错误弹窗修饰器
struct SaveErrorAlert: ViewModifier {
    @Binding var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .alert("保存失败", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好的", role: .cancel) { errorMessage = nil }
                Button("重试") {
                    // 重试由调用方处理
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "未知错误，请稍后再试")
            }
    }
}

extension View {
    func saveErrorAlert(_ errorMessage: Binding<String?>) -> some View {
        modifier(SaveErrorAlert(errorMessage: errorMessage))
    }
}

// MARK: - 数据自检修复

@MainActor
final class DataRepairService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    struct RepairReport {
        var orphanedTransactions: Int = 0   // 没有分类的交易
        var duplicateCategories: Int = 0     // 重复分类
        var invalidAmounts: Int = 0          // 金额异常
        var missingLedgers: Int = 0          // 没有账本的交易
        var totalFixed: Int { orphanedTransactions + duplicateCategories + invalidAmounts + missingLedgers }
        var summary: String {
            if totalFixed == 0 { return "✅ 数据一切正常，无需修复！" }
            var parts: [String] = []
            if orphanedTransactions > 0 { parts.append("修复 \(orphanedTransactions) 笔无分类交易") }
            if duplicateCategories > 0 { parts.append("清理 \(duplicateCategories) 个重复分类") }
            if invalidAmounts > 0 { parts.append("修正 \(invalidAmounts) 笔异常金额") }
            if missingLedgers > 0 { parts.append("修复 \(missingLedgers) 笔无账本交易") }
            return "🔧 共修复 \(totalFixed) 项：\n" + parts.joined(separator: "\n")
        }
    }

    func runRepair() -> RepairReport {
        var report = RepairReport()

        // 1. 修复没有分类的交易 → 设置为第一个支出/收入分类
        let allTransactions = (try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? []
        let expenseCategories = (try? modelContext.fetch(
            FetchDescriptor<Category>(predicate: #Predicate<Category> { $0.isExpense == true && $0.isArchived == false })
        )) ?? []
        let incomeCategories = (try? modelContext.fetch(
            FetchDescriptor<Category>(predicate: #Predicate<Category> { $0.isExpense == false && $0.isArchived == false })
        )) ?? []

        for t in allTransactions {
            if t.category == nil {
                t.category = t.isExpense ? expenseCategories.first : incomeCategories.first
                report.orphanedTransactions += 1
            }
        }

        // 2. 修复金额异常（<= 0）的交易
        for t in allTransactions {
            if t.amount <= 0 {
                t.amount = Decimal(1) // 设为最小有效值
                report.invalidAmounts += 1
            }
        }

        // 3. 修复没有账本的交易 → 分配到默认账本
        let ledgers = (try? modelContext.fetch(FetchDescriptor<Ledger>())) ?? []
        let defaultLedger = ledgers.first(where: { $0.isDefault }) ?? ledgers.first
        if let defaultLedger {
            for t in allTransactions {
                if t.ledger == nil {
                    t.ledger = defaultLedger
                    report.missingLedgers += 1
                }
            }
        }

        try? modelContext.save()
        return report
    }
}

// MARK: - 触觉反馈

enum HapticManager {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
