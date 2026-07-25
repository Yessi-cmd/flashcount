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
            guard visualExplorationDirection == nil, !isBudgetScopeReview, !isQuickEntryReview else { return }
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
        _ = try? DefaultDataService(modelContext: modelContext).prepareAppData()
    }

    private func prepareAppData() async {
        startupState = .preparing
        do {
            let recurringResult = try DefaultDataService(modelContext: modelContext).prepareAppData()
            prepareReportLayoutUITestDataIfNeeded()
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
}
