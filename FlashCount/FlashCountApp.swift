import SwiftUI
import SwiftData

@main
struct FlashCountApp: App {
    private let modelContainer: ModelContainer?
    private let modelContainerError: String?

    init() {
        FlashCountShortcuts.refreshSystemRegistration()
        ReminderNotificationService.configure()
        do {
            modelContainer = try ModelContainer(
                for: Schema(versionedSchema: FlashCountSchemaV2.self),
                migrationPlan: FlashCountMigrationPlan.self
            )
            modelContainerError = nil
        } catch {
            modelContainer = nil
            modelContainerError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                AppRootView()
                    .modelContainer(modelContainer)
            } else {
                StartupFailureView(
                    title: "无法打开本地账本",
                    message: "FlashCount 没有删除任何数据。请保留设备上的 App 数据，并重启 App 或联系支持。\n\n\(modelContainerError ?? "未知存储错误")"
                )
            }
        }
    }
}

private struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = AppearancePreference.light.rawValue
    @StateObject private var privacyLock = PrivacyLockService()
    @State private var startupState: StartupState = .preparing
    @State private var backgroundTaskError: String?
    @State private var startupAttempt = 0

    private enum StartupState: Equatable {
        case preparing
        case ready
        case failed(String)
    }

    var body: some View {
        Group {
#if DEBUG
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
                mainAppContent
            }
#else
            mainAppContent
#endif
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
            } else if phase == .active, startupState == .ready {
                rebuildNotificationSchedule()
            }
        }
        .task(id: startupAttempt) {
#if DEBUG
            guard visualExplorationDirection == nil, !isBudgetScopeReview, !isQuickEntryReview else { return }
#endif
            await prepareAppData()
        }
        .alert("后台处理未完成", isPresented: Binding(
            get: { backgroundTaskError != nil },
            set: { if !$0 { backgroundTaskError = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(backgroundTaskError ?? "请稍后在周期性规则中重试。")
        }
    }

    @ViewBuilder
    private var mainAppContent: some View {
        switch startupState {
        case .preparing:
            ProgressView("正在准备本地账本…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            MainTabView()
                .environmentObject(privacyLock)
        case .failed(let message):
            StartupFailureView(
                title: "本地数据准备失败",
                message: message,
                retry: { startupAttempt += 1 }
            )
        }
    }

#if DEBUG
    /// Debug-only visual lab. Production builds compile none of this —
    /// the exploration views themselves are also `#if DEBUG`.
    private var visualExplorationDirection: VisualDirection? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-visualDirectionExploration") || arguments.contains("-visualHomeExploration") else { return nil }
        if arguments.contains("-visualDirectionB") { return .soft }
        if arguments.contains("-visualDirectionC") { return .precise }
        return .restrained
    }

    private var isBudgetScopeReview: Bool {
        ProcessInfo.processInfo.arguments.contains("-visualBudgetScopeReview")
    }

    private var isQuickEntryReview: Bool {
        ProcessInfo.processInfo.arguments.contains("-visualQuickEntryReview")
    }

    private func prepareReviewDataIfNeeded() {
        _ = try? DefaultDataService(modelContext: modelContext).prepareAppData()
    }
#endif

    private func prepareAppData() async {
        startupState = .preparing
        do {
            let recurringResult = try DefaultDataService(modelContext: modelContext).prepareAppData()
            prepareReportLayoutUITestDataIfNeeded()
            prepareActionCenterUITestDataIfNeeded()
            startupState = .ready
            rebuildNotificationSchedule()
            if recurringResult.hasRemainingDueRules {
                Task { await continueRecurringProcessing() }
            }
        } catch {
            startupState = .failed("数据没有被删除或覆盖。请重试；若问题持续，请先导出或保留现有 App 数据后联系支持。\n\n\(error.localizedDescription)")
        }
    }

    private func continueRecurringProcessing() async {
        do {
            var result = try RecurringService(modelContext: modelContext).processDueRules()
            while result.hasRemainingDueRules {
                await Task.yield()
                result = try RecurringService(modelContext: modelContext).processDueRules()
            }
        } catch {
            backgroundTaskError = "周期交易尚未全部生成：\(error.localizedDescription)。请在“周期性规则”中重试。"
        }
    }

    private func rebuildNotificationSchedule() {
        do {
            let reminders = try ReminderDataService(modelContext: modelContext).load()
            Task {
                do {
                    try await NotificationScheduleCoordinator.shared.rebuild(reminders: reminders)
                } catch {
                    backgroundTaskError = "提醒通知未能更新：\(error.localizedDescription)。请在设置中检查通知权限后重试。"
                }
            }
        } catch {
            backgroundTaskError = "提醒通知未能读取本地数据：\(error.localizedDescription)。"
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

    /// Adds deterministic local-only data for the action-center UI smoke test.
    private func prepareActionCenterUITestDataIfNeeded() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-uiTestActionCenter") else { return }

        let marker = "__ui_test_action_center__"
        let existingTransactions = try? modelContext.fetch(FetchDescriptor<Transaction>())
        guard existingTransactions?.contains(where: { $0.note.hasPrefix(marker) }) != true else { return }

        let calendar = Calendar.current
        let now = Date.now
        guard let category = (try? modelContext.fetch(
            FetchDescriptor<Category>(
                predicate: #Predicate<Category> {
                    $0.name == "餐饮" && $0.isExpense && !$0.isArchived
                }
            )
        ))?.first else { return }

        let cycle = PayCycleService.cycle(containing: now, payday: 1, calendar: calendar)
        modelContext.insert(
            Budget(
                monthlyLimit: 100,
                year: cycle.budgetYear,
                month: cycle.budgetMonth
            )
        )
        modelContext.insert(
            Transaction(
                amount: 150,
                note: "\(marker).budget",
                date: now.addingTimeInterval(-3_600),
                category: category
            )
        )

        for monthOffset in [-2, -1, 0] {
            let date = calendar.date(byAdding: .month, value: monthOffset, to: now) ?? now
            modelContext.insert(
                Transaction(
                    amount: 12,
                    note: "\(marker).suggestion",
                    date: date,
                    category: category
                )
            )
        }

        let upcomingRuleDate = calendar.date(byAdding: .day, value: 3, to: now) ?? now
        modelContext.insert(
            RecurringRule(
                title: "测试周期扣款",
                amount: 28,
                frequency: .monthly,
                nextDueDate: upcomingRuleDate,
                category: category
            )
        )

        let overdueRuleDate = calendar.date(byAdding: .day, value: -2, to: now) ?? now
        modelContext.insert(
            RecurringRule(
                title: "测试待补周期账",
                amount: 16,
                frequency: .monthly,
                nextDueDate: overdueRuleDate,
                category: category
            )
        )

        let installmentDate = calendar.date(byAdding: .day, value: 2, to: now) ?? now
        let repaymentDay = calendar.component(.day, from: installmentDate)
        modelContext.insert(
            InstallmentBill(
                name: "测试设备分期",
                totalAmount: 120,
                installmentCount: 3,
                repaymentDay: repaymentDay,
                firstRepaymentDate: installmentDate
            )
        )

        let reminderDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        modelContext.insert(
            Reminder(
                item: ReminderItem(
                    title: "测试行动提醒",
                    dueDate: reminderDate
                )
            )
        )

        try? modelContext.save()
#endif
    }
}
