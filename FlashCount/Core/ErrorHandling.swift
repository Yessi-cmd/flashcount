import SwiftUI
import SwiftData

// MARK: - 保存错误处理

/// 安全保存，失败时记录错误信息并回滚内存状态
/// 回滚防止「下一个成功保存」固化不一致的内存状态
@MainActor
@discardableResult
func safeSave(_ context: ModelContext) -> String? {
    do {
        try context.save()
        return nil
    } catch {
        context.rollback()
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
        var missingLedgersFixed: Int = 0
        var uncategorizedTransactions: Int = 0
        var invalidAmountTransactions: Int = 0

        var totalFixed: Int { missingLedgersFixed }

        var summary: String {
            var parts: [String] = []
            if missingLedgersFixed > 0 { parts.append("已将 \(missingLedgersFixed) 笔无账本交易归入生活账本") }
            if uncategorizedTransactions > 0 { parts.append("发现 \(uncategorizedTransactions) 笔未分类交易，未自动猜测分类") }
            if invalidAmountTransactions > 0 { parts.append("发现 \(invalidAmountTransactions) 笔非正金额交易，未篡改金额") }
            return parts.isEmpty ? "✅ 数据一切正常，无需修复！" : parts.joined(separator: "\n")
        }
    }

    func runRepair() throws -> RepairReport {
        var report = RepairReport()

        let allTransactions = try modelContext.fetch(FetchDescriptor<Transaction>())
        report.uncategorizedTransactions = allTransactions.filter { $0.category == nil }.count
        report.invalidAmountTransactions = allTransactions.filter { $0.amount <= 0 }.count

        let ledgers = try modelContext.fetch(FetchDescriptor<Ledger>())
        let defaultLedger: Ledger
        if let existing = ledgers.first(where: { $0.isDefault }) ?? ledgers.first {
            defaultLedger = existing
        } else {
            defaultLedger = Ledger.defaultLedgers()[0]
            modelContext.insert(defaultLedger)
        }

        for transaction in allTransactions where transaction.ledger == nil {
            transaction.ledger = defaultLedger
            report.missingLedgersFixed += 1
        }

        guard modelContext.hasChanges else { return report }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        return report
    }
}

// MARK: - 触觉反馈

enum HapticManager {
    private static let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func success() {
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
    }

    static func error() {
        notificationGenerator.notificationOccurred(.error)
        notificationGenerator.prepare()
    }

    static func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    /// Prepares the generators used by the category wheel before the first
    /// sector is reached, avoiding delayed feedback during a continuous drag.
    static func prepareCategoryWheel() {
        lightImpactGenerator.prepare()
        mediumImpactGenerator.prepare()
        selectionGenerator.prepare()
    }

    static func categoryWheelOpened() {
        lightImpactGenerator.impactOccurred()
        prepareCategoryWheel()
    }

    static func categoryWheelSectorChanged() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    static func categoryWheelConfirmed() {
        mediumImpactGenerator.impactOccurred(intensity: 0.78)
        prepareCategoryWheel()
    }
}
