import SwiftUI
import SwiftData

@main
struct FlashCountApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.dark)
                .onAppear {
                    setupInitialData()
                }
        }
        .modelContainer(for: [
            Transaction.self,
            Category.self,
            Ledger.self,
            RecurringRule.self,
            Budget.self,
            Asset.self
        ])
    }

    /// 首次启动初始化默认数据
    @MainActor
    private func setupInitialData() {
        guard let container = try? ModelContainer(for: Transaction.self, Category.self, Ledger.self, RecurringRule.self, Budget.self, Asset.self) else { return }
        let context = container.mainContext

        // 检查是否已初始化
        let ledgerCount = (try? context.fetchCount(FetchDescriptor<Ledger>())) ?? 0
        if ledgerCount > 0 { return }

        // 创建默认账本
        for ledger in Ledger.defaultLedgers() {
            context.insert(ledger)
        }

        // 创建默认分类
        for category in Category.defaultExpenseCategories() {
            context.insert(category)
        }
        for category in Category.defaultIncomeCategories() {
            context.insert(category)
        }

        try? context.save()

        // 处理周期规则
        let recurringService = RecurringService(modelContext: context)
        recurringService.processAllDueRules()
    }
}
