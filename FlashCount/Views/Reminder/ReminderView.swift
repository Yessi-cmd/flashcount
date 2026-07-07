import SwiftUI
import UserNotifications

struct ReminderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reminders: [ReminderItem] = []
    @State private var showAddReminder = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var saveError: String?
    private let onClose: (() -> Void)?

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    private var activeReminders: [ReminderItem] {
        reminders
            .filter { !$0.isCompleted }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var completedReminders: [ReminderItem] {
        reminders
            .filter(\.isCompleted)
            .sorted { ($0.completedAt ?? $0.dueDate) > ($1.completedAt ?? $1.dueDate) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()

                List {
                    permissionSection

                    Section {
                        if activeReminders.isEmpty {
                            emptyActiveState
                        } else {
                            ForEach(activeReminders) { reminder in
                                ReminderRow(reminder: reminder) {
                                    close(reminder)
                                }
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            close(reminder)
                                        } label: {
                                            Label("关闭", systemImage: "bell.slash")
                                        }
                                        .tint(DesignSystem.incomeColor)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            delete(reminder)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    } header: {
                        Text("待提醒").foregroundStyle(DesignSystem.textSecondary)
                    }
                    .listRowBackground(DesignSystem.cardBackground)

                    if !completedReminders.isEmpty {
                        Section {
                            ForEach(completedReminders) { reminder in
                                ReminderRow(reminder: reminder)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            delete(reminder)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                            }
                        } header: {
                            Text("已完成").foregroundStyle(DesignSystem.textSecondary)
                        }
                        .listRowBackground(DesignSystem.cardBackground)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("提醒事项")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { close() }
                        .foregroundStyle(DesignSystem.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddReminder = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(DesignSystem.primaryColor)
                    }
                }
            }
            .sheet(isPresented: $showAddReminder) {
                AddReminderView { reminder in
                    add(reminder)
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好的") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .onAppear {
                reminders = ReminderStore.load()
                refreshNotificationStatus()
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
                Spacer()
                if notificationStatus == .notDetermined {
                    Button("开启") {
                        requestNotifications()
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DesignSystem.primaryColor)
                }
            }
        }
        .listRowBackground(DesignSystem.cardBackground)
    }

    private var emptyActiveState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 36))
                .foregroundStyle(DesignSystem.textTertiary)
            Text("暂无待提醒事项")
                .font(.subheadline)
                .foregroundStyle(DesignSystem.textSecondary)
            Button("添加提醒") {
                showAddReminder = true
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(DesignSystem.primaryColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
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
        case .notDetermined: return "开启提醒通知"
        @unknown default: return "通知状态未知"
        }
    }

    private var notificationStatusSubtitle: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return "强提醒会使用时间敏感通知，并在到点后追加几次提醒。"
        case .denied:
            return "需要到系统设置里允许通知，否则只能在 App 内查看。"
        case .notDetermined:
            return "允许通知后，未来某天某时刻才能准时提醒。"
        @unknown default:
            return "请检查系统通知设置。"
        }
    }

    private func add(_ reminder: ReminderItem) {
        reminders.append(reminder)
        persistAndSchedule(reminder)
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func close(_ reminder: ReminderItem) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        reminders[index].isCompleted = true
        reminders[index].completedAt = Date()
        ReminderNotificationService.cancel(reminderID: reminder.id)
        persist()
    }

    private func delete(_ reminder: ReminderItem) {
        reminders.removeAll { $0.id == reminder.id }
        ReminderNotificationService.cancel(reminderID: reminder.id)
        persist()
    }

    private func persistAndSchedule(_ reminder: ReminderItem) {
        persist()
        Task {
            let status = await ReminderNotificationService.authorizationStatus()
            if status == .notDetermined {
                _ = await ReminderNotificationService.requestAuthorization()
            }
            do {
                try await ReminderNotificationService.schedule(reminder)
            } catch {
                saveError = "通知安排失败：\(error.localizedDescription)"
            }
            refreshNotificationStatus()
        }
    }

    private func persist() {
        do {
            try ReminderStore.save(reminders)
        } catch {
            saveError = "提醒保存失败：\(error.localizedDescription)"
        }
    }

    private func refreshNotificationStatus() {
        Task {
            notificationStatus = await ReminderNotificationService.authorizationStatus()
        }
    }

    private func requestNotifications() {
        Task {
            _ = await ReminderNotificationService.requestAuthorization()
            refreshNotificationStatus()
        }
    }
}

private struct ReminderRow: View {
    let reminder: ReminderItem
    var onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reminder.intensity.iconName)
                .font(.headline)
                .foregroundStyle(iconColor)
                .frame(width: 34, height: 34)
                .background(iconColor.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(reminder.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(reminder.isCompleted ? DesignSystem.textTertiary : DesignSystem.textPrimary)
                        .lineLimit(1)
                    if reminder.isOverdue {
                        Text("已过期")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(DesignSystem.dangerColor)
                    }
                }
                Text(reminder.dueDate.reminderDateTimeString)
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textSecondary)
                if !reminder.note.isEmpty {
                    Text(reminder.note)
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text(reminder.intensity.rawValue)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(iconColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(iconColor.opacity(0.1))
                    .clipShape(Capsule())

                if let onClose, !reminder.isCompleted {
                    Button {
                        onClose()
                    } label: {
                        Label("关闭", systemImage: "bell.slash.fill")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(DesignSystem.incomeColor)
                    .accessibilityLabel("关闭提醒")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var iconColor: Color {
        if reminder.isCompleted { return DesignSystem.textTertiary }
        if reminder.isOverdue { return DesignSystem.dangerColor }
        return reminder.intensity == .strong ? DesignSystem.warningColor : DesignSystem.primaryColor
    }
}

private struct AddReminderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var note = ""
    @State private var dueDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var intensity: ReminderIntensity = .strong
    let onSave: (ReminderItem) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()

                Form {
                    Section {
                        TextField("例如：交房租、复诊、抢票", text: $title)
                            .foregroundStyle(DesignSystem.textPrimary)
                        TextField("备注，可不填", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                            .foregroundStyle(DesignSystem.textPrimary)
                    } header: {
                        Text("事项").foregroundStyle(DesignSystem.textSecondary)
                    }

                    Section {
                        DatePicker("提醒时间", selection: $dueDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .foregroundStyle(DesignSystem.textPrimary)
                    } header: {
                        Text("时间").foregroundStyle(DesignSystem.textSecondary)
                    }

                    Section {
                        Picker("提醒力度", selection: $intensity) {
                            ForEach(ReminderIntensity.allCases) { item in
                                Text(item.rawValue).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)

                        HStack(spacing: 10) {
                            Image(systemName: intensity.iconName)
                                .foregroundStyle(intensity == .strong ? DesignSystem.warningColor : DesignSystem.primaryColor)
                            Text(intensity.description)
                                .font(.caption)
                                .foregroundStyle(DesignSystem.textSecondary)
                        }
                    } header: {
                        Text("提醒方式").foregroundStyle(DesignSystem.textSecondary)
                    } footer: {
                        Text("iOS 不允许普通 App 像系统闹钟一样持续响铃，强提醒会用多次时间敏感通知增强存在感。")
                            .foregroundStyle(DesignSystem.textTertiary)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("新建提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(DesignSystem.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        let reminder = ReminderItem(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                            dueDate: dueDate,
                            intensity: intensity
                        )
                        onSave(reminder)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundStyle(DesignSystem.primaryColor)
                }
            }
        }
    }
}

private extension Date {
    var reminderDateTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDate(self, equalTo: Date(), toGranularity: .year)
            ? "M月d日 HH:mm"
            : "yyyy年M月d日 HH:mm"
        return formatter.string(from: self)
    }
}
