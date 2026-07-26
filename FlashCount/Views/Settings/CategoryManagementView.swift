import SwiftUI
import SwiftData

/// 分类的增删改与合并。所有写操作都走 `CategoryManagementService`，
/// 因为改名与合并会牵连交易、周期规则、预算和模板的引用。
struct CategoryManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var isExpense = true
    @State private var showEditor = false
    @State private var editingCategory: Category?
    @State private var initialParent: Category?
    @State private var mergeSource: Category?
    @State private var pendingArchive: Category?
    @State private var errorMessage: String?

    private struct RowModel: Identifiable {
        var id: UUID { category.id }
        let category: Category
        let isChild: Bool
    }

    private var activeRoots: [Category] {
        Category.rootCategories(from: categories, isExpense: isExpense)
    }

    private var activeRows: [RowModel] {
        activeRoots.flatMap { root in
            [RowModel(category: root, isChild: false)]
                + Category.childCategories(for: root.name, in: categories, isExpense: isExpense)
                    .map { RowModel(category: $0, isChild: true) }
        }
    }

    private var archivedCategories: [Category] {
        categories
            .filter { $0.isExpense == isExpense && $0.isArchived }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("收支类型", selection: $isExpense) {
                        Text("支出").tag(true)
                        Text("收入").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(DesignSystem.cardBackground)

                Section {
                    ForEach(activeRows) { row in
                        categoryRow(row)
                    }
                } header: {
                    Text("正在使用")
                } footer: {
                    Text("点击编辑；长按可排序、添加子分类、合并或归档。一级分类的排序会同步到记账分类轮盘。")
                }
                .listRowBackground(DesignSystem.cardBackground)

                if !archivedCategories.isEmpty {
                    Section("已归档") {
                        ForEach(archivedCategories, id: \.id) { category in
                            archivedRow(category)
                        }
                    }
                    .listRowBackground(DesignSystem.cardBackground)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignSystem.surfaceBackground)
            .navigationTitle("分类管理")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(DesignSystem.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentEditor(category: nil, parent: nil)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("添加一级分类")
                    .accessibilityIdentifier("categories.add")
                }
            }
            .sheet(isPresented: $showEditor, onDismiss: clearEditor) {
                CategoryEditorView(
                    category: editingCategory,
                    isExpense: editingCategory?.isExpense ?? isExpense,
                    initialParent: initialParent
                )
            }
            .sheet(item: $mergeSource) { source in
                CategoryMergeView(source: source)
            }
            .confirmationDialog("归档分类？", isPresented: Binding(
                get: { pendingArchive != nil },
                set: { if !$0 { pendingArchive = nil } }
            ), titleVisibility: .visible) {
                Button("归档", role: .destructive) {
                    if let pendingArchive { archive(pendingArchive) }
                    pendingArchive = nil
                }
                Button("取消", role: .cancel) { pendingArchive = nil }
            } message: {
                if let pendingArchive {
                    Text(pendingArchive.rootCategoryName == pendingArchive.name
                         ? "「\(pendingArchive.name)」及其子分类会从记账选择中隐藏，历史账单仍会保留。"
                         : "「\(pendingArchive.name)」会从记账选择中隐藏，历史账单仍会保留。")
                }
            }
            .alert("分类操作失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func categoryRow(_ row: RowModel) -> some View {
        Button {
            presentEditor(category: row.category, parent: nil)
        } label: {
            HStack(spacing: 12) {
                if row.isChild {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textTertiary)
                        .frame(width: 14)
                }
                categoryIcon(row.category)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.category.name)
                        .font(.subheadline.weight(row.isChild ? .regular : .semibold))
                        .foregroundStyle(DesignSystem.textPrimary)
                    Text(row.isChild ? "属于 \(row.category.rootCategoryName)" : "一级分类")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                presentEditor(category: row.category, parent: nil)
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            if !row.isChild {
                Button {
                    presentEditor(category: nil, parent: row.category)
                } label: {
                    Label("添加子分类", systemImage: "plus.square.on.square")
                }
            }
            Button { move(row.category, direction: .up) } label: {
                Label("上移", systemImage: "arrow.up")
            }
            .disabled(!canMove(row.category, direction: .up))
            Button { move(row.category, direction: .down) } label: {
                Label("下移", systemImage: "arrow.down")
            }
            .disabled(!canMove(row.category, direction: .down))
            Button {
                mergeSource = row.category
            } label: {
                Label("合并到…", systemImage: "arrow.triangle.merge")
            }
            Button(role: .destructive) {
                pendingArchive = row.category
            } label: {
                Label("归档", systemImage: "archivebox")
            }
        }
    }

    private func archivedRow(_ category: Category) -> some View {
        HStack(spacing: 12) {
            categoryIcon(category)
                .opacity(0.65)
            VStack(alignment: .leading, spacing: 3) {
                Text(category.name)
                    .font(.subheadline)
                    .foregroundStyle(DesignSystem.textSecondary)
                if let mergedID = category.mergedIntoCategoryID,
                   let target = categories.first(where: { $0.id == mergedID }) {
                    Text("已合并到 \(target.name)")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.textTertiary)
                } else {
                    Text(category.rootCategoryName == category.name ? "一级分类" : "属于 \(category.rootCategoryName)")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.textTertiary)
                }
            }
            Spacer()
            if category.mergedIntoCategoryID == nil {
                Button("恢复") { restore(category) }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.primaryColor)
            }
        }
    }

    private func categoryIcon(_ category: Category) -> some View {
        Image(systemName: category.icon)
            .font(.subheadline)
            .foregroundStyle(Color(hex: category.colorHex))
            .frame(width: 34, height: 34)
            .background(Color(hex: category.colorHex).opacity(0.12))
            .clipShape(Circle())
    }

    private func presentEditor(category: Category?, parent: Category?) {
        editingCategory = category
        initialParent = parent
        showEditor = true
    }

    private func clearEditor() {
        editingCategory = nil
        initialParent = nil
    }

    private func archive(_ category: Category) {
        perform { try CategoryManagementService(modelContext: modelContext).archive(category) }
    }

    private func restore(_ category: Category) {
        perform { try CategoryManagementService(modelContext: modelContext).restore(category) }
    }

    private func move(_ category: Category, direction: CategoryManagementService.MoveDirection) {
        perform { try CategoryManagementService(modelContext: modelContext).move(category, direction: direction) }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            HapticManager.selection()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.error()
        }
    }

    private func canMove(_ category: Category, direction: CategoryManagementService.MoveDirection) -> Bool {
        let siblings: [Category]
        if category.rootCategoryName == category.name {
            siblings = activeRoots
        } else {
            siblings = Category.childCategories(
                for: category.rootCategoryName,
                in: categories,
                isExpense: category.isExpense
            )
        }
        guard let index = siblings.firstIndex(where: { $0.id == category.id }) else { return false }
        switch direction {
        case .up: return index > 0
        case .down: return index < siblings.count - 1
        }
    }
}

private struct CategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    let category: Category?
    let isExpense: Bool
    let initialParent: Category?

    @State private var name = ""
    @State private var icon = "tag.fill"
    @State private var colorHex = "#4E766A"
    @State private var parentID: UUID?
    @State private var didLoad = false
    @State private var errorMessage: String?

    private let icons = [
        "fork.knife", "cup.and.saucer.fill", "cart.fill", "bag.fill", "house.fill", "car.fill",
        "tram.fill", "airplane", "gamecontroller.fill", "figure.run", "cross.case.fill", "pills.fill",
        "book.fill", "graduationcap.fill", "briefcase.fill", "banknote.fill", "gift.fill", "heart.fill",
        "pawprint.fill", "leaf.fill", "sparkles", "bolt.fill", "repeat", "ellipsis.circle.fill",
    ]
    private let colors = [
        "#FF7A70", "#FF9F43", "#F7B267", "#F6C667", "#70D6A3", "#45C4B0",
        "#5BC0EB", "#4D96FF", "#7B8CDE", "#B28DFF", "#FF8FAB", "#9AA6B2",
    ]

    private var possibleParents: [Category] {
        Category.rootCategories(from: categories, isExpense: isExpense)
            .filter { $0.id != category?.id }
    }

    private var hasChildren: Bool {
        guard let category else { return false }
        return !Category.childCategories(
            for: category.name,
            in: categories,
            isExpense: category.isExpense
        ).isEmpty
    }

    private var canSave: Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleanName.isEmpty && cleanName.count <= 24
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("分类名称", text: $name)
                    Text(isExpense ? "支出分类" : "收入分类")
                        .font(.caption)
                        .foregroundStyle(isExpense ? DesignSystem.expenseColor : DesignSystem.incomeColor)
                }

                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(icons, id: \.self) { candidate in
                            Button {
                                icon = candidate
                            } label: {
                                Image(systemName: candidate)
                                    .font(.headline)
                                    .foregroundStyle(icon == candidate ? .white : Color(hex: colorHex))
                                    .frame(width: 38, height: 38)
                                    .background(icon == candidate ? Color(hex: colorHex) : Color(hex: colorHex).opacity(0.12))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("颜色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(colors, id: \.self) { candidate in
                            Button {
                                colorHex = candidate
                            } label: {
                                Circle()
                                    .fill(Color(hex: candidate))
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if colorHex == candidate {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    if hasChildren {
                        LabeledContent("层级", value: "一级分类")
                        Text("包含子分类的一级分类不能直接移动到另一分类下。")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.textTertiary)
                    } else {
                        Picker("所属一级分类", selection: $parentID) {
                            Text("无（一级分类）").tag(nil as UUID?)
                            ForEach(possibleParents, id: \.id) { parent in
                                Text(parent.name).tag(parent.id as UUID?)
                            }
                        }
                    }
                } header: {
                    Text("层级")
                } footer: {
                    Text("子分类会显示在一级分类的轮盘中，报表和分类预算按一级分类汇总。")
                }
            }
            .navigationTitle(category == nil ? "添加分类" : "编辑分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear { loadIfNeeded() }
            .alert("无法保存分类", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let category {
            name = category.name
            icon = category.icon
            colorHex = category.colorHex
            if category.rootCategoryName != category.name {
                parentID = categories.first(where: {
                    $0.isExpense == category.isExpense && $0.name == category.rootCategoryName
                })?.id
            }
        } else {
            parentID = initialParent?.id
            if let initialParent {
                colorHex = initialParent.colorHex
            }
        }
    }

    private func save() {
        let parent = parentID.flatMap { id in categories.first(where: { $0.id == id }) }
        do {
            let service = CategoryManagementService(modelContext: modelContext)
            if let category {
                try service.update(category, name: name, icon: icon, colorHex: colorHex, parent: parent)
            } else {
                try service.create(name: name, icon: icon, colorHex: colorHex, isExpense: isExpense, parent: parent)
            }
            HapticManager.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.error()
        }
    }
}

private struct CategoryMergeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    let source: Category
    @State private var targetID: UUID?
    @State private var showConfirmation = false
    @State private var errorMessage: String?

    private var sourceHasChildren: Bool {
        categories.contains {
            $0.id != source.id
                && $0.isExpense == source.isExpense
                && $0.rootCategoryName == source.name
        }
    }

    private var candidates: [Category] {
        categories.filter {
            $0.id != source.id
                && $0.isExpense == source.isExpense
                && !$0.isArchived
                && $0.mergedIntoCategoryID == nil
                && (!sourceHasChildren || $0.rootCategoryName == $0.name)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("来源")
                        Spacer()
                        Label(source.name, systemImage: source.icon)
                            .foregroundStyle(Color(hex: source.colorHex))
                    }
                }

                Section("合并到") {
                    ForEach(candidates, id: \.id) { candidate in
                        Button {
                            targetID = candidate.id
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: candidate.icon)
                                    .foregroundStyle(Color(hex: candidate.colorHex))
                                    .frame(width: 30)
                                VStack(alignment: .leading) {
                                    Text(candidate.name)
                                        .foregroundStyle(DesignSystem.textPrimary)
                                    if candidate.rootCategoryName != candidate.name {
                                        Text("属于 \(candidate.rootCategoryName)")
                                            .font(.caption2)
                                            .foregroundStyle(DesignSystem.textTertiary)
                                    }
                                }
                                Spacer()
                                if targetID == candidate.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(DesignSystem.primaryColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Text("历史账单、周期规则、分类预算和记账模板会迁移到目标分类。若两边在同一周期都有预算，预算上限会相加。此操作不可直接撤销。")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textSecondary)
                }
            }
            .navigationTitle("合并分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("合并", role: .destructive) { showConfirmation = true }
                        .disabled(targetID == nil)
                }
            }
            .confirmationDialog("确认合并？", isPresented: $showConfirmation, titleVisibility: .visible) {
                Button("合并", role: .destructive) { merge() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("「\(source.name)」将归档，相关数据迁移到「\(targetName)」。")
            }
            .alert("合并失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var targetName: String {
        targetID.flatMap { id in categories.first(where: { $0.id == id })?.name } ?? "目标分类"
    }

    private func merge() {
        guard let targetID,
              let target = categories.first(where: { $0.id == targetID }) else { return }
        do {
            try CategoryManagementService(modelContext: modelContext).merge(source, into: target)
            HapticManager.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.error()
        }
    }
}
