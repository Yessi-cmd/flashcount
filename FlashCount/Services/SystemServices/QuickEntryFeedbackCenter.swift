import Foundation
import SwiftData
import SwiftUI

/// 记账保存后的反馈通道。
///
/// 保存成功过去是一张全屏遮罩，必须点「完成」或「再记一笔」才能走掉——每记一笔
/// 都要多按一次，而这一下恰好落在任务已经完成的那一刻。现在 sheet 立刻关闭，
/// 确认、预算提醒和撤销一起交给主界面上的短暂提示条：既省掉那次点击，
/// 又第一次给了「刚记错了」一条出路。
///
/// 提示条渲染在 `MainTabView`，所以无论从哪个 tab 或哪个入口保存都看得到。
@MainActor
final class QuickEntryFeedbackCenter: ObservableObject {
    struct SavedEntry: Identifiable, Equatable {
        let id: UUID
        /// 撤销时按 ID 重新取模型，而不是持有对象——中途被别处删掉也不会拿到失效引用。
        let transactionID: PersistentIdentifier
        let amount: Decimal
        let isExpense: Bool
        let categoryName: String
        let backdatedText: String?
        let budgetReminder: String?
        let budgetAlertLevel: BudgetAlertLevel?

        init(
            id: UUID = UUID(),
            transactionID: PersistentIdentifier,
            amount: Decimal,
            isExpense: Bool,
            categoryName: String,
            backdatedText: String? = nil,
            budgetReminder: String? = nil,
            budgetAlertLevel: BudgetAlertLevel? = nil
        ) {
            self.id = id
            self.transactionID = transactionID
            self.amount = amount
            self.isExpense = isExpense
            self.categoryName = categoryName
            self.backdatedText = backdatedText
            self.budgetReminder = budgetReminder
            self.budgetAlertLevel = budgetAlertLevel
        }

        var headline: String {
            "已记\(isExpense ? "支出" : "收入") \(amount.formattedCurrency)"
        }

        var detail: String {
            [categoryName, backdatedText]
                .compactMap { $0 }
                .joined(separator: " · ")
        }
    }

    @Published private(set) var lastSaved: SavedEntry?

    /// 提示条是撤销的时间窗，不是常驻状态；几秒后自己收起。
    static let defaultVisibleDuration: Duration = .seconds(5)

    /// 可注入，好让过期行为能在测试里用毫秒级窗口验证，而不是让测试等 5 秒。
    private let visibleDuration: Duration
    private var expiryTask: Task<Void, Never>?

    /// 默认值在 init 体内解析，而不是写成默认实参：默认实参在 nonisolated 上下文
    /// 里求值，引用 `@MainActor` 隔离的静态属性在 Swift 6 语言模式下是错误。
    init(visibleDuration: Duration? = nil) {
        self.visibleDuration = visibleDuration ?? Self.defaultVisibleDuration
    }

    func present(_ entry: SavedEntry) {
        expiryTask?.cancel()
        lastSaved = entry
        let duration = visibleDuration
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.lastSaved = nil
        }
    }

    func dismiss() {
        expiryTask?.cancel()
        expiryTask = nil
        lastSaved = nil
    }
}
