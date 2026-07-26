import SwiftUI

/// 新增或编辑一条提醒。
struct AddReminderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var note = ""
    @State private var dueDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var intensity: ReminderIntensity = .strong
    let onSave: (ReminderItem) -> Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("事项") {
                    TextField("例如：交房租、复诊、抢票", text: $title)
                    TextField("备注，可不填", text: $note, axis: .vertical).lineLimit(2...4)
                }
                Section("时间") {
                    DatePicker("提醒时间", selection: $dueDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                }
                Section {
                    Picker("提醒力度", selection: $intensity) {
                        ForEach(ReminderIntensity.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Label(intensity.description, systemImage: intensity.iconName)
                        .font(.caption)
                        .foregroundStyle(intensity == .strong ? DesignSystem.warningColor : DesignSystem.primaryColor)
                } header: {
                    Text("提醒方式")
                } footer: {
                    Text("iOS 不允许普通 App 像系统闹钟一样持续响铃，强提醒会用多次时间敏感通知增强存在感。")
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignSystem.surfaceBackground)
            .navigationTitle("新建提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        let reminder = ReminderItem(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                            dueDate: dueDate,
                            intensity: intensity
                        )
                        if onSave(reminder) { dismiss() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .tint(DesignSystem.primaryColor)
        }
    }
}

extension Date {
    var reminderDateTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDate(self, equalTo: Date(), toGranularity: .year)
            ? "M月d日 HH:mm"
            : "yyyy年M月d日 HH:mm"
        return formatter.string(from: self)
    }
}
