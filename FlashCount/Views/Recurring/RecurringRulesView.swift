import SwiftUI
import SwiftData

/// 周期性规则管理页面
struct RecurringRulesView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var privacyLock: PrivacyLockService
    @Query(sort: \RecurringRule.createdAt, order: .reverse) private var rules: [RecurringRule]
    @State private var showAddRule = false
    @State private var editingRule: RecurringRule?
    @State private var rulePendingDeletion: RecurringRule?
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        if rules.isEmpty { emptyState }
                        else {
                            ForEach(rules, id: \.id) { rule in
                                ruleCard(rule)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("周期账单")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddRule = true } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(DesignSystem.primaryColor)
                    }
                }
            }
            .sheet(isPresented: $showAddRule) { AddRecurringRuleView() }
            .sheet(isPresented: Binding(
                get: { editingRule != nil },
                set: { if !$0 { editingRule = nil } }
            )) {
                if let editingRule {
                    AddRecurringRuleView(editRule: editingRule)
                }
            }
            .confirmationDialog("删除周期账单？", isPresented: Binding(
                get: { rulePendingDeletion != nil },
                set: { if !$0 { rulePendingDeletion = nil } }
            ), titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if let rule = rulePendingDeletion {
                        delete(rule)
                    }
                    rulePendingDeletion = nil
                }
                Button("取消", role: .cancel) {
                    rulePendingDeletion = nil
                }
            } message: {
                Text("只删除这条自动入账规则，已经生成的交易记录会保留。")
            }
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

    private func ruleCard(_ rule: RecurringRule) -> some View {
        let hidesPrivateIncome = rule.isProtectedIncome && !privacyLock.isUnlocked
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill((hidesPrivateIncome ? DesignSystem.textTertiary : Color(hex: rule.category?.colorHex ?? "#667EEA")).opacity(0.15)).frame(width: 44, height: 44)
                Image(systemName: hidesPrivateIncome ? "lock.fill" : rule.category?.icon ?? "repeat").font(.title3)
                    .foregroundStyle(hidesPrivateIncome ? DesignSystem.textTertiary : Color(hex: rule.category?.colorHex ?? "#667EEA"))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(hidesPrivateIncome ? "隐私收入" : rule.title).font(.subheadline.weight(.medium)).foregroundStyle(DesignSystem.textPrimary)
                    if !rule.isActive {
                        Text("已暂停").font(.caption2).foregroundStyle(DesignSystem.textTertiary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(DesignSystem.softFill).clipShape(Capsule())
                    }
                }
                Text("\(rule.frequency.rawValue) · 下次: \(rule.nextDueDate.shortDateString)")
                    .font(.caption).foregroundStyle(DesignSystem.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(rule.amount.formattedCurrency)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(rule.isExpense ? DesignSystem.expenseColor : DesignSystem.incomeColor)
                    .privacySensitive(hidesPrivateIncome)
                    .opacity(hidesPrivateIncome ? 0 : 1)
                    .overlay {
                        if hidesPrivateIncome {
                            Text(privacyLock.maskedText)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(DesignSystem.textTertiary)
                        }
                    }
                HStack(spacing: 8) {
                    Button {
                        toggle(rule)
                    } label: {
                        Image(systemName: rule.isActive ? "pause.circle" : "play.circle")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(rule.isActive ? "暂停周期账单" : "恢复周期账单")

                    Menu {
                        Button {
                            if hidesPrivateIncome {
                                Task { _ = await privacyLock.unlock() }
                            } else {
                                editingRule = rule
                            }
                        } label: {
                            Label(hidesPrivateIncome ? "解锁查看" : "编辑", systemImage: hidesPrivateIncome ? "lock.open" : "pencil")
                        }
                        Button(role: .destructive) {
                            rulePendingDeletion = rule
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.textTertiary)
                    }
                }
            }
        }
        .glassCard()
        .opacity(rule.isActive ? 1 : 0.6)
        .contentShape(Rectangle())
        .onTapGesture {
            if hidesPrivateIncome {
                Task { _ = await privacyLock.unlock() }
            } else {
                editingRule = rule
            }
        }
        .contextMenu {
            Button {
                if hidesPrivateIncome {
                    Task { _ = await privacyLock.unlock() }
                } else {
                    editingRule = rule
                }
            } label: {
                Label(hidesPrivateIncome ? "解锁查看" : "编辑", systemImage: hidesPrivateIncome ? "lock.open" : "pencil")
            }
            Button {
                toggle(rule)
            } label: {
                Label(rule.isActive ? "暂停" : "恢复", systemImage: rule.isActive ? "pause.circle" : "play.circle")
            }
            Button(role: .destructive) {
                rulePendingDeletion = rule
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "repeat").font(.system(size: 50)).foregroundStyle(DesignSystem.textTertiary)
            Text("暂无周期账单").font(.headline).foregroundStyle(DesignSystem.textSecondary)
            Text("添加房租、话费、会员等固定服务，自动生成记录").font(.subheadline).foregroundStyle(DesignSystem.textTertiary).multilineTextAlignment(.center)
            Button { showAddRule = true } label: {
                Text("添加周期账单").font(.subheadline.weight(.semibold)).foregroundStyle(DesignSystem.textPrimary)
                    .padding(.horizontal, 24).padding(.vertical, 12).background(DesignSystem.primaryGradient).clipShape(Capsule())
            }
        }.padding(.vertical, 60)
    }

    private func toggle(_ rule: RecurringRule) {
        rule.isActive.toggle()
        persist()
    }

    private func delete(_ rule: RecurringRule) {
        modelContext.delete(rule)
        persist()
    }

    private func persist() {
        do {
            try modelContext.save()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
