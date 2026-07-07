import SwiftUI
import SwiftData

@main
struct FlashCountApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(for: [
            Transaction.self,
            Category.self,
            Ledger.self,
            RecurringRule.self,
            Budget.self,
            Asset.self,
            PhysicalAsset.self,
            CashPoolItem.self,
            CashPoolState.self,
            SavingsGoal.self,
            InstallmentBill.self,
            TransactionTemplate.self
        ])
    }
}

private struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = AppearancePreference.light.rawValue
    @StateObject private var privacyLock = PrivacyLockService()
    private static var didPrepareData = false

    var body: some View {
        MainTabView()
            .environmentObject(privacyLock)
            .preferredColorScheme(AppearancePreference(rawValue: appearance)?.colorScheme)
            .onAppear {
                ReminderNotificationService.configure()
                guard !Self.didPrepareData else { return }
                Self.didPrepareData = true
                DefaultDataService(modelContext: modelContext).prepareAppData()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    privacyLock.lock()
                }
            }
    }
}
