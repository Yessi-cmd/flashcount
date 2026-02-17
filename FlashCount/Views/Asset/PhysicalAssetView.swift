import SwiftUI
import SwiftData

/// 实物资产追踪器 - 主页面
struct PhysicalAssetView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PhysicalAsset.purchaseDate, order: .reverse) private var assets: [PhysicalAsset]
    @State private var showAddAsset = false
    @State private var editingAsset: PhysicalAsset?

    private var activeAssets: [PhysicalAsset] { assets.filter { !$0.isArchived } }
    private var archivedAssets: [PhysicalAsset] { assets.filter { $0.isArchived } }

    /// 总持有价值
    private var totalValue: Decimal {
        activeAssets.reduce(Decimal(0)) { $0 + $1.currentValue }
    }

    /// 平均日成本
    private var averageDailyCost: Decimal {
        guard !activeAssets.isEmpty else { return 0 }
        return activeAssets.reduce(Decimal(0)) { $0 + $1.dailyCost } / Decimal(activeAssets.count)
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
        }
    }

    // MARK: - 概览

    private var overviewCard: some View {
        VStack(spacing: 16) {
            Text("持有资产价值").font(.subheadline).foregroundStyle(.white.opacity(0.5))
            Text(totalValue.formattedCurrency)
                .font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(.white)
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("持有数量").font(.caption).foregroundStyle(.white.opacity(0.4))
                    Text("\(activeAssets.count) 件")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.primaryColor)
                }
                Rectangle().fill(.white.opacity(0.1)).frame(width: 1, height: 30)
                VStack(spacing: 4) {
                    Text("平均日成本").font(.caption).foregroundStyle(.white.opacity(0.4))
                    Text(averageDailyCost.formattedCurrency)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24).glassCard()
    }

    // MARK: - 资产列表

    private var activeAssetList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("持有中").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.7))
            ForEach(activeAssets.sorted { $0.dailyCost > $1.dailyCost }, id: \.id) { asset in
                PhysicalAssetCard(asset: asset)
                    .onTapGesture { editingAsset = asset }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            modelContext.delete(asset); try? modelContext.save()
                        } label: { Label("删除", systemImage: "trash") }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            asset.isArchived = true
                            try? modelContext.save()
                        } label: { Label("已出", systemImage: "checkmark.circle") }
                        .tint(.green)
                    }
            }
        }
    }

    private var archivedAssetList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("已出售 / 归档").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.4))
            ForEach(archivedAssets, id: \.id) { asset in
                HStack(spacing: 12) {
                    Image(systemName: asset.category.icon)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.name).font(.subheadline).foregroundStyle(.white.opacity(0.5))
                        Text("持有 \(asset.daysHeld) 天 · 日均 \(asset.dailyCost.formattedCurrency)")
                            .font(.caption).foregroundStyle(.white.opacity(0.3))
                    }
                    Spacer()
                    if let profit = asset.actualProfit {
                        Text((profit >= 0 ? "+" : "") + profit.formattedCurrency)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(profit >= 0 ? DesignSystem.incomeColor : DesignSystem.expenseColor)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .glassCard()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.and.arrow.forward").font(.system(size: 50)).foregroundStyle(.white.opacity(0.2))
            Text("追踪你的实物资产").font(.headline).foregroundStyle(.white.opacity(0.5))
            Text("记录电子产品、汽车等，看看每天花多少钱").font(.subheadline).foregroundStyle(.white.opacity(0.3))
            Button { showAddAsset = true } label: {
                Text("添加资产").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(DesignSystem.primaryGradient).clipShape(Capsule())
            }
        }.padding(.vertical, 60)
    }
}

/// 资产卡片
struct PhysicalAssetCard: View {
    let asset: PhysicalAsset

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
                        .foregroundStyle(.white)
                    Text("\(asset.category.rawValue) · 持有 \(asset.daysHeld) 天")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(asset.purchasePrice.formattedCurrency)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                    Text("日均 \(asset.dailyCost.formattedCurrency)")
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
                                .fill(.white.opacity(0.06))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(progressColor)
                                .frame(width: geo.size.width * asset.progressToTarget, height: 6)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text("\(Int(asset.progressToTarget * 100))%")
                            .font(.caption2.weight(.medium).monospacedDigit())
                            .foregroundStyle(progressColor)
                        Spacer()
                        if let remaining = asset.daysToTarget, remaining > 0 {
                            Text("还需 \(remaining) 天达标 🎯")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.4))
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
                        .foregroundStyle(.white.opacity(0.3))
                    Spacer()
                }
            }
        }
        .padding()
        .background(.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .stroke(.white.opacity(0.06), lineWidth: 1)
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

    var isEditing: Bool { editAsset != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // 类别选择
                        VStack(alignment: .leading, spacing: 8) {
                            Text("类别").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
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
                                                    .background(category == cat ? DesignSystem.primaryColor.opacity(0.2) : .white.opacity(0.06))
                                                    .foregroundStyle(category == cat ? DesignSystem.primaryColor : .white.opacity(0.5))
                                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                                Text(cat.rawValue).font(.caption2).foregroundStyle(.white.opacity(0.6))
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
                            Text("购买价格").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
                            HStack {
                                Text("¥").font(.title3).foregroundStyle(.white.opacity(0.5))
                                TextField("0", text: $purchasePriceText)
                                    .keyboardType(.decimalPad)
                                    .font(.title3.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(.white)
                                    .onChange(of: purchasePriceText) { updateDefaults() }
                            }
                            .padding(12).background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                        }

                        // 购买日期
                        VStack(alignment: .leading, spacing: 8) {
                            Text("购买日期").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
                            DatePicker("", selection: $purchaseDate, displayedComponents: .date)
                                .datePickerStyle(.compact).labelsHidden().colorScheme(.dark)
                        }

                        // 预估残值
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("预估残值（转手价）").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
                                Spacer()
                                Text("默认 \(Int(category.defaultSalvageRatio * 100))%")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.3))
                            }
                            HStack {
                                Text("¥").font(.subheadline).foregroundStyle(.white.opacity(0.5))
                                TextField("0", text: $salvageValueText)
                                    .keyboardType(.decimalPad)
                                    .font(.subheadline).monospacedDigit().foregroundStyle(.white)
                            }
                            .padding(12).background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                        }

                        // 目标日成本
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("目标日成本").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
                                Spacer()
                                Text("每天花不超过这个数就算值").font(.caption2).foregroundStyle(.white.opacity(0.3))
                            }
                            HStack {
                                Text("¥").font(.subheadline).foregroundStyle(.white.opacity(0.5))
                                TextField("0", text: $targetDailyCostText)
                                    .keyboardType(.decimalPad)
                                    .font(.subheadline).monospacedDigit().foregroundStyle(.white)
                                Text("/天").font(.caption).foregroundStyle(.white.opacity(0.3))
                            }
                            .padding(12).background(.white.opacity(0.06))
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
                    Button("取消") { dismiss() }.foregroundStyle(.white.opacity(0.7))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || purchasePriceText.isEmpty)
                        .foregroundStyle(DesignSystem.primaryColor)
                }
            }
            .onAppear { loadEditData() }
        }
    }

    private func inputField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
            TextField(placeholder, text: text).font(.subheadline).foregroundStyle(.white)
                .padding(12).background(.white.opacity(0.06))
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
        try? modelContext.save()
        dismiss()
    }
}
