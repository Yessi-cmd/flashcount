import SwiftUI
import SwiftData

/// 模板横条 — 显示在 QuickEntryView 顶部，一键填入金额 / 分类 / 备注
struct TemplateBarView: View {
    @Query(sort: \TransactionTemplate.sortOrder) private var templates: [TransactionTemplate]

    let expenseCategories: [Category]
    let incomeCategories: [Category]
    let onSelect: (TransactionTemplate, Category?) -> Void
    let onManage: () -> Void
    var onEditTemplate: ((TransactionTemplate) -> Void)?

    private var currentCategories: [Category] {
        // 合并所有分类，onSelect 时根据模板的 isExpense 决定用哪一组
        expenseCategories + incomeCategories
    }

    @ViewBuilder
    var body: some View {
        if templates.isEmpty {
            emptyView
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.warningColor)
                Text("记账模板")
                    .font(DesignSystem.Typography.compactLabelEmphasized)
                    .foregroundStyle(DesignSystem.textSecondary)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(templates, id: \.id) { template in
                        templateButton(template)
                    }
                    // 管理按钮
                    Button {
                        onManage()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.caption)
                            Text("管理")
                                .font(DesignSystem.Typography.compactLabel)
                        }
                        .foregroundStyle(DesignSystem.textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .background(DesignSystem.softFill)
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, DesignSystem.cardPadding)
        .padding(.vertical, 12)
        .background(DesignSystem.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .stroke(DesignSystem.borderColor, lineWidth: 1)
        )
    }

    private func templateButton(_ template: TransactionTemplate) -> some View {
        Button {
            let pool = template.isExpense ? expenseCategories : incomeCategories
            let category = template.categoryName
                .flatMap { name in pool.first { $0.name == name } }
                // 在预期池中没找到时，尝试在另一个池中查找（应对分类被重命名的情况）
                ?? template.categoryName
                    .flatMap { name in
                        let otherPool = template.isExpense ? incomeCategories : expenseCategories
                        return otherPool.first { $0.name == name }
                    }
            onSelect(template, category)
            HapticManager.selection()
        } label: {
            HStack(spacing: 6) {
                Text(template.name)
                    .font(DesignSystem.Typography.compactLabelEmphasized)
                Text(template.amount.formattedAmount)
                    .font(DesignSystem.Typography.supportingLabel)
                    .foregroundStyle(
                        template.isExpense
                        ? DesignSystem.expenseColor
                        : DesignSystem.incomeColor
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                template.isExpense
                ? DesignSystem.expenseColor.opacity(0.08)
                : DesignSystem.incomeColor.opacity(0.08)
            )
            .foregroundStyle(DesignSystem.textPrimary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        template.isExpense
                        ? DesignSystem.expenseColor.opacity(0.15)
                        : DesignSystem.incomeColor.opacity(0.15),
                        lineWidth: 1
                    )
            )
        }
        .contextMenu {
            if let onEditTemplate {
                Button {
                    onEditTemplate(template)
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
            }
        }
    }

    @ViewBuilder
    private var emptyView: some View {
        Color.clear.frame(height: 0)
    }
}
