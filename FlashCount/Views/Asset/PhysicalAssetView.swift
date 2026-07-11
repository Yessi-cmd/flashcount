import SwiftUI
import SwiftData

/// 实物资产追踪器 - 主页面
struct PhysicalAssetView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var privacyLock: PrivacyLockService
    @Query(sort: \PhysicalAsset.purchaseDate, order: .reverse) private var assets: [PhysicalAsset]
    @State private var showAddAsset = false
    @State private var editingAsset: PhysicalAsset?
    @State private var sellingAsset: PhysicalAsset?
    @State private var confirmDeleteAsset: PhysicalAsset?
    @State private var saveError: String?
    @AppStorage("hideAssetBalance") private var hideAssetBalance = true

    private var activeAssets: [PhysicalAsset] { assets.filter { !$0.isArchived } }
    private var archivedAssets: [PhysicalAsset] { assets.filter { $0.isArchived } }

    /// 总持有价值（折旧后）
    private var totalValue: Decimal {
        activeAssets.reduce(Decimal(0)) { $0 + $1.currentValue }
    }

    /// 原价总值
    private var totalPurchasePrice: Decimal {
        activeAssets.reduce(Decimal(0)) { $0 + $1.purchasePrice }
    }

    /// 平均日成本
    private var averageDailyCost: Decimal {
        guard !activeAssets.isEmpty else { return 0 }
        return activeAssets.reduce(Decimal(0)) { $0 + $1.dailyCost } / Decimal(activeAssets.count)
    }

    private var hidesMoney: Bool {
        hideAssetBalance || !privacyLock.isUnlocked
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: DesignSystem.sectionSpacing) {
                        // 概览卡片
                        overviewCard
                        // 活跃资产列表
                        if !activeAssets.isEmpty { activeAssetList }
                        // 已出售/归档
                        if !archivedAssets.isEmpty { archivedAssetList }
                        // 空状态
                        if assets.isEmpty { emptyState }
                    }
                    .padding()
                }
            }
            .navigationTitle("实物资产")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddAsset = true } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(DesignSystem.primaryColor)
                    }
                }
            }
            .sheet(isPresented: $showAddAsset) { AddPhysicalAssetView() }
            .sheet(item: $editingAsset) { asset in
                AddPhysicalAssetView(editAsset: asset)
            }
            .sheet(item: $sellingAsset) { asset in
                SellPhysicalAssetView(asset: asset)
            }
            .saveErrorAlert($saveError)
            .alert("确认删除", isPresented: .init(
                get: { confirmDeleteAsset != nil },
                set: { if !$0 { confirmDeleteAsset = nil } }
            )) {
                Button("取消", role: .cancel) { confirmDeleteAsset = nil }
                Button("删除", role: .destructive) {
                    if let asset = confirmDeleteAsset {
                        withAnimation {
                            modelContext.delete(asset)
                            if let error = safeSave(modelContext) {
                                // 静默处理：资产页面没有单独的 saveError state
                                print("删除实物资产失败: \(error)")
                            }
                        }
                    }
                    confirmDeleteAsset = nil
                }
            } message: {
                Text("删除后无法恢复，确定要删除「\(confirmDeleteAsset?.name ?? "")」吗？")
            }
        }
    }

    // MARK: - 概览

    private var overviewCard: some View {
        VStack(spacing: 16) {
            Text("持有资产估值").font(.subheadline).foregroundStyle(DesignSystem.textSecondary)
            Text(hidesMoney ? privacyLock.maskedText : totalValue.formattedCurrency)
                .font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(DesignSystem.textPrimary)
            Text("原价合计 \(hidesMoney ? privacyLock.maskedText : totalPurchasePrice.formattedCurrency)")
                .font(.caption).foregroundStyle(DesignSystem.textTertiary)
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("持有数量").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                    Text("\(activeAssets.count) 件")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.primaryColor)
                }
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 30)
                VStack(spacing: 4) {
                    Text("平均日成本").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                    Text(hidesMoney ? privacyLock.maskedText : averageDailyCost.formattedCurrency)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.orange)
                }
                Rectangle().fill(DesignSystem.dividerColor).frame(width: 1, height: 30)
                VStack(spacing: 4) {
                    Text("总折旧").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                    Text(hidesMoney ? privacyLock.maskedText : (totalPurchasePrice - totalValue).formattedCurrency)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(DesignSystem.expenseColor)
                }
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24).glassCard()
    }

    // MARK: - 资产列表

    private var activeAssetList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("持有中").font(.subheadline.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
            ForEach(activeAssets.sorted { $0.dailyCost > $1.dailyCost }, id: \.id) { asset in
                PhysicalAssetCard(asset: asset, hidesMoney: hidesMoney, maskedText: privacyLock.maskedText)
                    .onTapGesture { editingAsset = asset }
                    .contextMenu {
                        Button {
                            editingAsset = asset
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        Button {
                            sellingAsset = asset
                        } label: {
                            Label("出售", systemImage: "yensign.circle")
                        }
                        Button(role: .destructive) {
                            confirmDeleteAsset = asset
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            confirmDeleteAsset = asset
                        } label: { Label("删除", systemImage: "trash") }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            sellingAsset = asset
                        } label: { Label("出售", systemImage: "yensign.circle") }
                        .tint(.green)
                    }
            }
        }
    }

    private var archivedAssetList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("已出售").font(.subheadline.weight(.medium)).foregroundStyle(DesignSystem.textTertiary)
            ForEach(archivedAssets, id: \.id) { asset in
                HStack(spacing: 12) {
                    Image(systemName: asset.category.icon)
                        .font(.subheadline)
                        .foregroundStyle(DesignSystem.textTertiary)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.name).font(.subheadline).foregroundStyle(DesignSystem.textSecondary)
                        Text(soldSummary(for: asset))
                            .font(.caption).foregroundStyle(DesignSystem.textTertiary)
                    }
                    Spacer()
                    if let profit = asset.actualProfit {
                        Text(hidesMoney ? privacyLock.maskedText : (profit >= 0 ? "+" : "") + profit.formattedCurrency)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(profit >= 0 ? DesignSystem.incomeColor : DesignSystem.expenseColor)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture { editingAsset = asset }
                .contextMenu {
                    Button {
                        editingAsset = asset
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    Button {
                        asset.isArchived = false
                        asset.soldPrice = nil
                        asset.soldDate = nil
                        if let error = safeSave(modelContext) {
                            saveError = error
                        }
                    } label: {
                        Label("恢复为持有中", systemImage: "arrow.uturn.backward")
                    }
                    Button(role: .destructive) {
                        confirmDeleteAsset = asset
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .glassCard()
    }

    private func soldSummary(for asset: PhysicalAsset) -> String {
        let soldText = asset.soldPrice.map { "卖出 \(hidesMoney ? privacyLock.maskedText : $0.formattedCurrency)" } ?? "未记录售价"
        let dailyText = asset.actualDailyCost.map { "实际日均 \(hidesMoney ? privacyLock.maskedText : $0.formattedCurrency)" } ?? "持有 \(asset.daysHeld) 天"
        return "\(soldText) · \(dailyText)"
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.and.arrow.forward").font(.system(size: 50)).foregroundStyle(DesignSystem.textTertiary)
            Text("追踪你的实物资产").font(.headline).foregroundStyle(DesignSystem.textSecondary)
            Text("记录电子产品、汽车等，看看每天花多少钱").font(.subheadline).foregroundStyle(DesignSystem.textTertiary)
            Button { showAddAsset = true } label: {
                Text("添加资产").font(.subheadline.weight(.semibold)).foregroundStyle(DesignSystem.textPrimary)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(DesignSystem.primaryGradient).clipShape(Capsule())
            }
        }.padding(.vertical, 60)
    }
}

/// 资产卡片
struct PhysicalAssetCard: View {
    let asset: PhysicalAsset
    let hidesMoney: Bool
    let maskedText: String

    var body: some View {
        VStack(spacing: 12) {
            // 头部：名称 + 类别
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(DesignSystem.primaryColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: asset.category.icon)
                        .font(.subheadline)
                        .foregroundStyle(DesignSystem.primaryColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DesignSystem.textPrimary)
                    Text("\(asset.category.rawValue) · 持有 \(asset.daysHeld) 天")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("估值 \(hidesMoney ? maskedText : asset.currentValue.formattedCurrency)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DesignSystem.textSecondary)
                    Text("日均 \(hidesMoney ? maskedText : asset.dailyCost.formattedCurrency)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.orange)
                }
            }

            // 进度条（仅有目标时显示）
            if asset.targetDailyCost > 0 {
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(DesignSystem.softFill)
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(progressColor)
                                .frame(width: hidesMoney ? 0 : geo.size.width * asset.progressToTarget, height: 6)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text(hidesMoney ? maskedText : "\(Int(asset.progressToTarget * 100))%")
                            .font(.caption2.weight(.medium).monospacedDigit())
                            .foregroundStyle(progressColor)
                        Spacer()
                        if let remaining = asset.daysToTarget, remaining > 0 {
                            Text("还需 \(remaining) 天达标 🎯")
                                .font(.caption2)
                                .foregroundStyle(DesignSystem.textTertiary)
                        } else if asset.dailyCost <= asset.targetDailyCost {
                            Text("已达到目标日成本 ✅")
                                .font(.caption2)
                                .foregroundStyle(DesignSystem.incomeColor)
                        }
                    }
                }
            } else {
                HStack {
                    Text("未设置目标日成本")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.textTertiary)
                    Spacer()
                }
            }
        }
        .padding()
        .background(DesignSystem.softFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .stroke(DesignSystem.borderColor, lineWidth: 1)
        )
    }

    private var progressColor: Color {
        asset.progressToTarget >= 1.0 ? DesignSystem.incomeColor :
        asset.progressToTarget >= 0.6 ? .orange :
        DesignSystem.primaryColor
    }
}

/// 添加/编辑实物资产
struct AddPhysicalAssetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var editAsset: PhysicalAsset?

    @State private var name = ""
    @State private var category: PhysicalAssetCategory = .phone
    @State private var purchasePriceText = ""
    @State private var purchaseDate = Date()
    @State private var salvageValueText = ""
    @State private var targetDailyCostText = ""
    @State private var note = ""
    @State private var saveError: String?

    var isEditing: Bool { editAsset != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // 类别选择
                        VStack(alignment: .leading, spacing: 8) {
                            Text("类别").font(.caption.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(PhysicalAssetCategory.allCases, id: \.self) { cat in
                                        Button {
                                            withAnimation(.spring(response: 0.3)) {
                                                category = cat
                                                updateDefaults()
                                            }
                                        } label: {
                                            VStack(spacing: 4) {
                                                Image(systemName: cat.icon)
                                                    .font(.title3)
                                                    .frame(width: 44, height: 44)
                                                    .background(category == cat ? DesignSystem.primaryColor.opacity(0.2) : DesignSystem.softFill)
                                                    .foregroundStyle(category == cat ? DesignSystem.primaryColor : DesignSystem.textSecondary)
                                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                                Text(cat.rawValue).font(.caption2).foregroundStyle(DesignSystem.textSecondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 名称
                        inputField(title: "名称", placeholder: "如：iPhone 15 Pro", text: $name)

                        // 购买价格
                        VStack(alignment: .leading, spacing: 8) {
                            Text("购买价格").font(.caption.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
                            HStack {
                                Text("¥").font(.title3).foregroundStyle(DesignSystem.textSecondary)
                                TextField("0", text: $purchasePriceText)
                                    .keyboardType(.decimalPad)
                                    .font(.title3.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(DesignSystem.textPrimary)
                                    .onChange(of: purchasePriceText) { updateDefaults() }
                            }
                            .padding(12).background(DesignSystem.softFill)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                        }

                        // 购买日期
                        VStack(alignment: .leading, spacing: 8) {
                            Text("购买日期").font(.caption.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
                            DatePicker("", selection: $purchaseDate, displayedComponents: .date)
                                .datePickerStyle(.compact).labelsHidden()
                        }

                        // 预估残值
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("预估残值（转手价）").font(.caption.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
                                Spacer()
                                Text("默认 \(Int(category.defaultSalvageRatio * 100))%")
                                    .font(.caption2).foregroundStyle(DesignSystem.textTertiary)
                            }
                            HStack {
                                Text("¥").font(.subheadline).foregroundStyle(DesignSystem.textSecondary)
                                TextField("0", text: $salvageValueText)
                                    .keyboardType(.decimalPad)
                                    .font(.subheadline).monospacedDigit().foregroundStyle(DesignSystem.textPrimary)
                            }
                            .padding(12).background(DesignSystem.softFill)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                        }

                        // 目标日成本
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("目标日成本").font(.caption.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
                                Spacer()
                                Text("每天花不超过这个数就算值").font(.caption2).foregroundStyle(DesignSystem.textTertiary)
                            }
                            HStack {
                                Text("¥").font(.subheadline).foregroundStyle(DesignSystem.textSecondary)
                                TextField("0", text: $targetDailyCostText)
                                    .keyboardType(.decimalPad)
                                    .font(.subheadline).monospacedDigit().foregroundStyle(DesignSystem.textPrimary)
                                Text("/天").font(.caption).foregroundStyle(DesignSystem.textTertiary)
                            }
                            .padding(12).background(DesignSystem.softFill)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                        }

                        // 备注
                        inputField(title: "备注", placeholder: "可选", text: $note)

                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle(isEditing ? "编辑资产" : "添加资产")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }.foregroundStyle(DesignSystem.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || purchasePriceText.isEmpty)
                        .foregroundStyle(DesignSystem.primaryColor)
                }
            }
            .onAppear { loadEditData() }
            .saveErrorAlert($saveError)
        }
    }

    private func inputField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
            TextField(placeholder, text: text).font(.subheadline).foregroundStyle(DesignSystem.textPrimary)
                .padding(12).background(DesignSystem.softFill)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
        }
    }

    private func updateDefaults() {
        guard let price = Decimal(string: purchasePriceText), price > 0 else { return }
        let salvage = price * Decimal(category.defaultSalvageRatio)
        if salvageValueText.isEmpty || Decimal(string: salvageValueText) == nil {
            salvageValueText = "\(salvage)"
        }
        let dailyCost = (price - salvage) / 365
        if targetDailyCostText.isEmpty || Decimal(string: targetDailyCostText) == nil {
            targetDailyCostText = "\(NSDecimalNumber(decimal: dailyCost).intValue)"
        }
    }

    private func loadEditData() {
        guard let asset = editAsset else { return }
        name = asset.name
        category = asset.category
        purchasePriceText = "\(asset.purchasePrice)"
        purchaseDate = asset.purchaseDate
        salvageValueText = "\(asset.salvageValue)"
        targetDailyCostText = "\(asset.targetDailyCost)"
        note = asset.note
    }

    private func save() {
        guard let price = Decimal(string: purchasePriceText), price > 0 else { return }
        let salvage = Decimal(string: salvageValueText)
        let targetDaily = Decimal(string: targetDailyCostText)

        if let asset = editAsset {
            asset.name = name
            asset.category = category
            asset.purchasePrice = price
            asset.purchaseDate = purchaseDate
            asset.salvageValue = salvage ?? (price * Decimal(category.defaultSalvageRatio))
            asset.targetDailyCost = targetDaily ?? ((price - asset.salvageValue) / 365)
            asset.note = note
        } else {
            let asset = PhysicalAsset(
                name: name, category: category, purchasePrice: price,
                purchaseDate: purchaseDate, salvageValue: salvage,
                targetDailyCost: targetDaily, note: note
            )
            modelContext.insert(asset)
        }
        if let error = safeSave(modelContext) {
            saveError = error
        } else {
            dismiss()
        }
    }
}

/// 出售实物资产
struct SellPhysicalAssetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var asset: PhysicalAsset

    @State private var soldPriceText: String
    @State private var soldDate: Date
    @State private var note: String
    @State private var saveError: String?

    init(asset: PhysicalAsset) {
        self.asset = asset
        _soldPriceText = State(initialValue: asset.soldPrice.map { "\($0)" } ?? "\(asset.currentValue)")
        _soldDate = State(initialValue: asset.soldDate ?? Date())
        _note = State(initialValue: asset.note)
    }

    private var previewProfit: Decimal? {
        guard let soldPrice = Decimal(string: soldPriceText) else { return nil }
        return soldPrice - asset.purchasePrice
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()

                VStack(spacing: 20) {
                    VStack(spacing: 10) {
                        Image(systemName: asset.category.icon)
                            .font(.title2)
                            .foregroundStyle(DesignSystem.primaryColor)
                            .frame(width: 54, height: 54)
                            .background(DesignSystem.primaryColor.opacity(0.12))
                            .clipShape(Circle())

                        Text(asset.name)
                            .font(.headline)
                            .foregroundStyle(DesignSystem.textPrimary)
                        Text("原价 \(asset.purchasePrice.formattedCurrency) · 已持有 \(asset.daysHeld) 天")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("出售价格")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DesignSystem.textSecondary)
                            HStack {
                                Text("¥")
                                    .font(.title3)
                                    .foregroundStyle(DesignSystem.textSecondary)
                                TextField("0", text: $soldPriceText)
                                    .keyboardType(.decimalPad)
                                    .font(.title3.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(DesignSystem.textPrimary)
                            }
                            .padding(12)
                            .background(DesignSystem.softFill)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("出售日期")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DesignSystem.textSecondary)
                            DatePicker("", selection: $soldDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("备注")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DesignSystem.textSecondary)
                            TextField("可选", text: $note)
                                .font(.subheadline)
                                .foregroundStyle(DesignSystem.textPrimary)
                                .padding(12)
                                .background(DesignSystem.softFill)
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                        }
                    }
                    .glassCard()

                    if let previewProfit {
                        HStack {
                            Text(previewProfit >= 0 ? "预计收益" : "预计亏损")
                                .font(.caption)
                                .foregroundStyle(DesignSystem.textSecondary)
                            Spacer()
                            Text((previewProfit >= 0 ? "+" : "") + previewProfit.formattedCurrency)
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(previewProfit >= 0 ? DesignSystem.incomeColor : DesignSystem.expenseColor)
                        }
                        .padding()
                        .background(DesignSystem.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
                        .overlay(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius).stroke(DesignSystem.borderColor))
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("出售资产")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(DesignSystem.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { saveSale() }
                        .disabled(Decimal(string: soldPriceText) == nil)
                        .foregroundStyle(DesignSystem.primaryColor)
                }
            }
            .saveErrorAlert($saveError)
        }
    }

    private func saveSale() {
        guard let soldPrice = Decimal(string: soldPriceText), soldPrice >= 0 else { return }
        asset.soldPrice = soldPrice
        asset.soldDate = soldDate
        asset.note = note
        asset.isArchived = true
        if let error = safeSave(modelContext) {
            saveError = error
        } else {
            dismiss()
        }
    }
}
