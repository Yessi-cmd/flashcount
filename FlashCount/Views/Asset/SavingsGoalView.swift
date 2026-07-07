import SwiftUI
import SwiftData

struct SavingsGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var privacyLock: PrivacyLockService
    @Query(sort: \SavingsGoal.createdAt, order: .reverse) private var goals: [SavingsGoal]

    @State private var showAddGoal = false
    @State private var editingGoal: SavingsGoal?
    @AppStorage("hideAssetBalance") private var hideAssetBalance = true

    private var activeGoals: [SavingsGoal] {
        goals.filter { !$0.isArchived }
    }

    private var hidesMoney: Bool {
        hideAssetBalance || !privacyLock.isUnlocked
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        if activeGoals.isEmpty {
                            emptyState
                        } else {
                            ForEach(activeGoals, id: \.id) { goal in
                                goalCard(goal)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("储蓄目标")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddGoal = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(DesignSystem.primaryColor)
                    }
                }
            }
            .sheet(isPresented: $showAddGoal) {
                AddSavingsGoalView()
            }
            .sheet(item: $editingGoal) { goal in
                AddSavingsGoalView(editGoal: goal)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "target")
                .font(.system(size: 48))
                .foregroundStyle(DesignSystem.textTertiary)
            Text("暂无储蓄目标")
                .font(.headline)
                .foregroundStyle(DesignSystem.textSecondary)
            Text("设一个想存下来的金额，再手动更新进度")
                .font(.subheadline)
                .foregroundStyle(DesignSystem.textTertiary)
            Button("添加目标") {
                showAddGoal = true
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .background(DesignSystem.primaryGradient)
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func goalCard(_ goal: SavingsGoal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.textPrimary)
                    if let targetDate = goal.targetDate {
                        Text("目标日 \(targetDate.shortDateString)")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.textTertiary)
                    }
                }
                Spacer()
                Text(hidesMoney ? privacyLock.maskedText : "\(Int(goal.progress * 100))%")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(DesignSystem.primaryColor)
            }

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 5)
                    .fill(DesignSystem.dividerColor)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(DesignSystem.primaryGradient)
                            .frame(width: hidesMoney ? 0 : geo.size.width * CGFloat(goal.progress))
                    }
            }
            .frame(height: 10)

            HStack(spacing: 0) {
                goalMetric(title: "已存", value: goal.currentAmount)
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 28)
                goalMetric(title: "目标", value: goal.targetAmount)
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 28)
                goalMetric(title: "还差", value: goal.remainingAmount)
            }

            if let suggestion = savingSuggestion(for: goal), !hidesMoney {
                Text(suggestion)
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textSecondary)
            }
        }
        .glassCard()
        .contentShape(Rectangle())
        .onTapGesture { editingGoal = goal }
        .contextMenu {
            Button { editingGoal = goal } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button {
                goal.isCompleted.toggle()
                goal.updatedAt = Date()
                try? modelContext.save()
            } label: {
                Label(goal.isCompleted ? "标记未完成" : "标记完成", systemImage: goal.isCompleted ? "circle" : "checkmark.circle")
            }
            Button(role: .destructive) {
                goal.isArchived = true
                goal.updatedAt = Date()
                try? modelContext.save()
            } label: {
                Label("归档", systemImage: "archivebox")
            }
        }
        .opacity(goal.isCompleted ? 0.68 : 1)
    }

    private func goalMetric(title: String, value: Decimal) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(DesignSystem.textTertiary)
            Text(hidesMoney ? privacyLock.maskedText : value.formattedCurrency)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(DesignSystem.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
    }

    private func savingSuggestion(for goal: SavingsGoal) -> String? {
        guard let targetDate = goal.targetDate, goal.remainingAmount > 0 else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDay = calendar.startOfDay(for: targetDate)
        let days = calendar.dateComponents([.day], from: today, to: targetDay).day ?? 0
        if days < 0 {
            return "目标日已过，还差 \(goal.remainingAmount.formattedCurrency)，建议调整目标日期"
        }
        if days == 0 {
            return "今天是目标日，还差 \(goal.remainingAmount.formattedCurrency)"
        }
        let daily = goal.remainingAmount / Decimal(days)
        let monthly = daily * 30
        return "还需约每天 \(daily.formattedCurrency)，每月 \(monthly.formattedCurrency)"
    }
}

private struct AddSavingsGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var editGoal: SavingsGoal?

    @State private var name = ""
    @State private var targetAmountText = ""
    @State private var currentAmountText = ""
    @State private var hasTargetDate = false
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var note = ""
    @State private var saveError: String?

    private var isEditing: Bool { editGoal != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                Form {
                    Section("目标") {
                        TextField("名称，例如：旅行基金", text: $name)
                        TextField("目标金额", text: $targetAmountText)
                            .keyboardType(.decimalPad)
                        TextField("当前已存", text: $currentAmountText)
                            .keyboardType(.decimalPad)
                    }
                    Section("日期") {
                        Toggle("设置目标日期", isOn: $hasTargetDate)
                        if hasTargetDate {
                            DatePicker("目标日期", selection: $targetDate, displayedComponents: .date)
                        }
                    }
                    Section("备注") {
                        TextField("备注", text: $note)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(isEditing ? "编辑目标" : "添加目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || targetAmountText.isEmpty)
                }
            }
            .onAppear(perform: load)
            .alert("保存失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好的") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func load() {
        guard let editGoal, name.isEmpty else { return }
        name = editGoal.name
        targetAmountText = NSDecimalNumber(decimal: editGoal.targetAmount).stringValue
        currentAmountText = NSDecimalNumber(decimal: editGoal.currentAmount).stringValue
        if let date = editGoal.targetDate {
            targetDate = date
            hasTargetDate = true
        }
        note = editGoal.note
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let targetAmount = Decimal(string: targetAmountText), targetAmount > 0, !cleanName.isEmpty else { return }
        let currentAmount = Decimal(string: currentAmountText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let date = hasTargetDate ? targetDate : nil

        if let editGoal {
            editGoal.name = cleanName
            editGoal.targetAmount = targetAmount
            editGoal.currentAmount = currentAmount
            editGoal.targetDate = date
            editGoal.note = note
            editGoal.isCompleted = currentAmount >= targetAmount
            editGoal.updatedAt = Date()
        } else {
            modelContext.insert(SavingsGoal(name: cleanName, targetAmount: targetAmount, currentAmount: currentAmount, targetDate: date, note: note))
        }

        if let error = safeSave(modelContext) {
            saveError = error
        } else {
            dismiss()
        }
    }
}
