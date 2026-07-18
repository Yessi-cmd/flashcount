import SwiftUI
import SwiftData

@main
struct FlashCountApp: App {
    init() {
        ReminderNotificationService.configure()
    }

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
            TransactionTemplate.self,
            Reminder.self
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
        Group {
            if isBudgetScopeReview {
                DailyBudgetScopeView()
                    .onAppear { prepareReviewDataIfNeeded() }
            } else if isQuickEntryReview {
                QuickEntryView()
                    .onAppear { prepareReviewDataIfNeeded() }
            } else if let direction = visualExplorationDirection {
                if ProcessInfo.processInfo.arguments.contains("-visualHomeExploration") {
                    MainInterfaceExplorationView(
                        initialDirection: direction,
                        allowsDirectionSwitching: !ProcessInfo.processInfo.arguments.contains("-visualDirectionSnapshot")
                    )
                } else {
                    VisualDirectionExplorationView(
                        initialDirection: direction,
                        allowsDirectionSwitching: !ProcessInfo.processInfo.arguments.contains("-visualDirectionSnapshot")
                    )
                }
            } else {
                MainTabView()
                    .environmentObject(privacyLock)
                    .onAppear {
                        guard !Self.didPrepareData else { return }
                        Self.didPrepareData = true
                        DefaultDataService(modelContext: modelContext).prepareAppData()
                        prepareReportLayoutUITestDataIfNeeded()
                        rebuildNotificationSchedule()
                    }
            }
        }
        .tint(DesignSystem.primaryColor)
        .fontDesign(.rounded)
        .preferredColorScheme(AppearancePreference(rawValue: appearance)?.colorScheme)
        .overlay {
            if scenePhase != .active {
                ZStack {
                    DesignSystem.surfaceBackground.ignoresSafeArea()
                    VStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.title2)
                        Text("隐私内容已遮挡")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(DesignSystem.textTertiary)
                }
                .accessibilityHidden(true)
            }
        }
        .confirmationDialog(
            "显示隐私金额？",
            isPresented: $privacyLock.isRevealConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("验证并显示") {
                Task { _ = await privacyLock.confirmReveal() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("验证后，本次使用期间会显示所有收入和资产金额。进入后台或点击眼睛按钮后会再次隐藏。")
        }
        .alert("无法显示隐私金额", isPresented: Binding(
            get: { privacyLock.lastError != nil },
            set: { if !$0 { privacyLock.lastError = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(privacyLock.lastError ?? "身份验证未完成")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                privacyLock.lock()
            } else if phase == .active, Self.didPrepareData {
                rebuildNotificationSchedule()
            }
        }
    }

    /// Debug-only visual lab. Production launches always keep the normal app root.
    private var visualExplorationDirection: VisualDirection? {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-visualDirectionExploration") || arguments.contains("-visualHomeExploration") else { return nil }
        if arguments.contains("-visualDirectionB") { return .soft }
        if arguments.contains("-visualDirectionC") { return .precise }
        return .restrained
#else
        return nil
#endif
    }

    private var isBudgetScopeReview: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-visualBudgetScopeReview")
#else
        false
#endif
    }

    private var isQuickEntryReview: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-visualQuickEntryReview")
#else
        false
#endif
    }

    private func prepareReviewDataIfNeeded() {
        guard !Self.didPrepareData else { return }
        Self.didPrepareData = true
        DefaultDataService(modelContext: modelContext).prepareAppData()
    }

    private func rebuildNotificationSchedule() {
        do {
            let reminders = try ReminderDataService(modelContext: modelContext).load()
            Task { _ = try? await NotificationScheduleCoordinator.shared.rebuild(reminders: reminders) }
        } catch {
            print("提醒通知重建前读取失败: \(error.localizedDescription)")
        }
    }

    /// 为底部遮挡回归测试提供一份足以生成完整报表、且可重复使用的本地数据。
    private func prepareReportLayoutUITestDataIfNeeded() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-uiTestReportLayout") else { return }

        let marker = "__ui_test_report_layout__"
        let transactionDescriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { transaction in
                transaction.note == marker
            }
        )
        let existingTransaction = (try? modelContext.fetch(transactionDescriptor))?.first

        var categoryDescriptor = FetchDescriptor<Category>(
            predicate: #Predicate<Category> { category in
                category.name == "餐饮" && category.isExpense && !category.isArchived
            }
        )
        categoryDescriptor.fetchLimit = 1
        let category = (try? modelContext.fetch(categoryDescriptor))?.first

        if let existingTransaction {
            existingTransaction.amount = Decimal(string: "51.90") ?? 51.9
            existingTransaction.isExpense = true
            existingTransaction.date = Date().addingTimeInterval(-60)
            existingTransaction.category = category
        } else {
            modelContext.insert(
                Transaction(
                    amount: Decimal(string: "51.90") ?? 51.9,
                    note: marker,
                    date: Date().addingTimeInterval(-60),
                    category: category
                )
            )
        }
        try? modelContext.save()
#endif
    }
}
