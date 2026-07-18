import SwiftUI
import SwiftData
import UserNotifications

struct ReportReminderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("payday") private var payday = 1

    @State private var preferences: ReportReminderPreferences
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var scheduleStatus = NotificationScheduleStatus.empty

    private let store: any ReportReminderPreferencesStoring
    private let scheduler: any ReportReminderNotificationScheduling

    init(
        store: any ReportReminderPreferencesStoring = UserDefaultsReportReminderPreferencesStore(),
        scheduler: any ReportReminderNotificationScheduling = SystemReportReminderNotificationScheduler()
    ) {
        let loaded = store.load()
        self.store = store
        self.scheduler = scheduler
        _preferences = State(initialValue: loaded)
    }

    var body: some View {
        NavigationStack {
            List {
                permissionSection
                scheduleStatusSection
                periodSection
                if !preferences.enabledPeriods.isEmpty {
                    deliverySection
                    scheduleDetailSections
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignSystem.surfaceBackground)
            .navigationTitle("报表提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(DesignSystem.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(isSaving)
                        .foregroundStyle(DesignSystem.primaryColor)
                }
            }
            .disabled(isSaving)
            .overlay {
                if isSaving {
                    ProgressView()
                        .padding(18)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .onAppear {
                refreshNotificationStatus()
                scheduleStatus = NotificationScheduleStatusStore().load()
            }
            .alert("无法保存报表提醒", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private var permissionSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: notificationStatusIcon)
                    .foregroundStyle(notificationStatusColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(notificationStatusTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DesignSystem.textPrimary)
                    Text(notificationStatusSubtitle)
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textTertiary)
                }
            }
        }
        .listRowBackground(DesignSystem.cardBackground)
    }

    @ViewBuilder
    private var scheduleStatusSection: some View {
        if let summary = scheduleStatus.summary {
            Section {
                Label(summary, systemImage: scheduleStatus.errorMessage == nil ? "clock.badge.exclamationmark" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(scheduleStatus.errorMessage == nil ? DesignSystem.warningColor : DesignSystem.dangerColor)
                    .accessibilityIdentifier("notification.scheduleStatus")
            } footer: {
                Text("iOS 最多保留 64 条待通知。FlashCount 按下一次触发时间优先安排；长期不打开 App 时，月报、年报和周期报无法无限自动补排。")
            }
            .listRowBackground(DesignSystem.cardBackground)
        }
    }

    private var periodSection: some View {
        Section("提醒周期") {
            ForEach(ReportPeriod.allCases, id: \.self) { period in
                Toggle(isOn: enabledBinding(for: period)) {
                    Label(period.rawValue, systemImage: periodIcon(period))
                        .foregroundStyle(DesignSystem.textPrimary)
                }
                .tint(DesignSystem.primaryColor)
            }
        }
        .listRowBackground(DesignSystem.cardBackground)
    }

    private var deliverySection: some View {
        Section("送达时间") {
            DatePicker(
                "每天在",
                selection: deliveryTimeBinding,
                displayedComponents: .hourAndMinute
            )
        }
        .listRowBackground(DesignSystem.cardBackground)
    }

    @ViewBuilder
    private var scheduleDetailSections: some View {
        if preferences.enabledPeriods.contains(.weekly) {
            Section("周报") {
                Picker("每周", selection: $preferences.weeklyDeliveryWeekday) {
                    ForEach(weekdayOptions, id: \.value) { option in
                        Text(option.title).tag(option.value)
                    }
                }
            }
            .listRowBackground(DesignSystem.cardBackground)
        }

        if preferences.enabledPeriods.contains(.monthly) {
            Section {
                Stepper("每月 \(preferences.monthlyDeliveryDay) 日", value: $preferences.monthlyDeliveryDay, in: 1...31)
            } header: {
                Text("月报")
            } footer: {
                Text("当月没有该日期时，会在当月最后一天提醒。")
            }
            .listRowBackground(DesignSystem.cardBackground)
        }

        if preferences.enabledPeriods.contains(.yearly) {
            Section {
                Picker("月份", selection: $preferences.yearlyDeliveryMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text("\(month) 月").tag(month)
                    }
                }
                Stepper("\(preferences.yearlyDeliveryDay) 日", value: $preferences.yearlyDeliveryDay, in: 1...31)
            } header: {
                Text("年报")
            } footer: {
                Text("日期超出所选月份时，会使用该月最后一天。")
            }
            .listRowBackground(DesignSystem.cardBackground)
        }

        if preferences.enabledPeriods.contains(.payCycle) {
            Section {
                LabeledContent("报告日", value: "每月 \(min(max(payday, 1), 31)) 日")
            } header: {
                Text("周期报")
            } footer: {
                Text("按设置中的发薪日生成刚结束的完整发薪周期报告。")
            }
            .listRowBackground(DesignSystem.cardBackground)
        }
    }

    private var deliveryTimeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(
                hour: preferences.deliveryTime.hour,
                minute: preferences.deliveryTime.minute
            )) ?? Date()
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            preferences.deliveryTime = ReportReminderTime(
                hour: components.hour ?? 20,
                minute: components.minute ?? 0
            )
        }
    }

    private func enabledBinding(for period: ReportPeriod) -> Binding<Bool> {
        Binding {
            preferences.enabledPeriods.contains(period)
        } set: { enabled in
            if enabled {
                preferences.enabledPeriods.insert(period)
            } else {
                preferences.enabledPeriods.remove(period)
            }
        }
    }

    private var weekdayOptions: [(value: Int, title: String)] {
        [(2, "周一"), (3, "周二"), (4, "周三"), (5, "周四"), (6, "周五"), (7, "周六"), (1, "周日")]
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            let normalized = preferences.normalized()

            if !normalized.enabledPeriods.isEmpty {
                var status = await scheduler.authorizationStatus()
                if status == .notDetermined {
                    _ = await scheduler.requestAuthorization()
                    status = await scheduler.authorizationStatus()
                }
                guard status == .authorized || status == .provisional || status == .ephemeral else {
                    errorMessage = "系统通知尚未开启。请先在 iOS 设置中允许 FlashCount 发送通知。"
                    return
                }
            }

            do {
                try store.save(normalized)
                do {
                    let reminders = try ReminderDataService(modelContext: modelContext).load()
                    try await scheduler.replaceSchedule(with: normalized, reminders: reminders)
                    scheduleStatus = NotificationScheduleStatusStore().load()
                    dismiss()
                } catch {
                    scheduleStatus = NotificationScheduleStatusStore().load()
                    errorMessage = "设置已保存，但通知安排失败：\(error.localizedDescription)"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func refreshNotificationStatus() {
        Task { notificationStatus = await scheduler.authorizationStatus() }
    }

    private var notificationStatusIcon: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "bell.badge.fill"
        case .denied: return "bell.slash.fill"
        case .notDetermined: return "bell.fill"
        @unknown default: return "bell.fill"
        }
    }

    private var notificationStatusColor: Color {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return DesignSystem.incomeColor
        case .denied: return DesignSystem.dangerColor
        case .notDetermined: return DesignSystem.warningColor
        @unknown default: return DesignSystem.warningColor
        }
    }

    private var notificationStatusTitle: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "通知已开启"
        case .denied: return "通知被关闭"
        case .notDetermined: return "保存时请求通知权限"
        @unknown default: return "通知状态未知"
        }
    }

    private var notificationStatusSubtitle: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "到期后点击通知会直接打开对应报表。"
        case .denied: return "需要到系统设置中允许通知。"
        case .notDetermined: return "只有启用至少一个周期时才会请求权限。"
        @unknown default: return "请检查系统通知设置。"
        }
    }

    private func periodIcon(_ period: ReportPeriod) -> String {
        switch period {
        case .daily: return "sun.max.fill"
        case .weekly: return "calendar"
        case .monthly: return "calendar.badge.clock"
        case .yearly: return "chart.line.uptrend.xyaxis"
        case .payCycle: return "arrow.triangle.2.circlepath"
        }
    }
}
