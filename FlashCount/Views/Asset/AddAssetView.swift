import SwiftUI
import SwiftData

/// 添加/编辑资产账户
struct AddAssetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var editAsset: Asset?

    @State private var name = ""
    @State private var type: AssetType = .bankCard
    @State private var balanceText = ""
    @State private var balanceError: MoneyValidationError?
    @State private var selectedColor = "#667EEA"
    @State private var saveError: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case balance
    }

    private var isEditing: Bool { editAsset != nil }

    private let colors = [
        "#667EEA", "#764BA2", "#F093FB", "#FC5C7D",
        "#FF6B6B", "#FFA502", "#2ED573", "#1E90FF",
        "#4ECDC4", "#A8E6CF", "#778BEB", "#E056A0"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.surfaceBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        // 账户名称
                        VStack(alignment: .leading, spacing: 8) {
                            Text("账户名称").font(.caption.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
                            TextField("例如：招商银行储蓄卡", text: $name)
                                .font(.body).foregroundStyle(DesignSystem.textPrimary).padding(12)
                                .background(DesignSystem.softFill)
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                        }

                        // 类型选择
                        VStack(alignment: .leading, spacing: 8) {
                            Text("账户类型").font(.caption.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                                ForEach(AssetType.allCases, id: \.rawValue) { assetType in
                                    Button {
                                        type = assetType
                                    } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: assetType.icon).font(.title3)
                                            Text(assetType.rawValue).font(.caption2)
                                        }
                                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                                        .background(type == assetType ? Color(hex: selectedColor).opacity(0.2) : DesignSystem.softFill)
                                        .foregroundStyle(type == assetType ? Color(hex: selectedColor) : DesignSystem.textSecondary)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                        }

                        // 余额
                        VStack(alignment: .leading, spacing: 8) {
                            Text(type.isLiability ? "欠款金额" : "当前余额").font(.caption.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
                            HStack {
                                Text("¥").font(.title3).foregroundStyle(DesignSystem.textSecondary)
                                TextField("0.00", text: $balanceText).keyboardType(.decimalPad)
                                    .font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(DesignSystem.textPrimary)
                                    .focused($focusedField, equals: .balance)
                                    .onChange(of: balanceText) { _, _ in balanceError = nil }
                            }
                            .padding(12).background(DesignSystem.softFill)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                            ValidationMessage(message: balanceError?.errorDescription)
                        }

                        // 颜色
                        VStack(alignment: .leading, spacing: 8) {
                            Text("颜色").font(.caption.weight(.medium)).foregroundStyle(DesignSystem.textSecondary)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                                ForEach(colors, id: \.self) { color in
                                    Button { selectedColor = color } label: {
                                        Circle().fill(Color(hex: color)).frame(width: 36, height: 36)
                                            .overlay(Circle().stroke(.white, lineWidth: selectedColor == color ? 3 : 0).padding(2))
                                    }
                                }
                            }
                        }

                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle(isEditing ? "编辑账户" : "添加账户").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }.foregroundStyle(DesignSystem.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { saveAsset() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || balanceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .foregroundStyle(DesignSystem.primaryColor)
                }
            }
            .onAppear {
                if let asset = editAsset {
                    name = asset.name
                    type = asset.type
                    balanceText = "\(asset.balance)"
                    selectedColor = asset.colorHex
                }
            }
            .saveErrorAlert($saveError)
        }
    }

    private func saveAsset() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        let balance: Decimal
        switch MoneyValidation.parse(balanceText, requirement: .nonNegative) {
        case .success(let value):
            balance = value
            balanceError = nil
        case .failure(let error):
            balanceError = error
            focusedField = .balance
            HapticManager.error()
            return
        }
        if let asset = editAsset {
            asset.name = cleanName
            asset.type = type
            asset.balance = balance
            asset.colorHex = selectedColor
            asset.updatedAt = Date()
        } else {
            let asset = Asset(name: cleanName, type: type, balance: balance, colorHex: selectedColor)
            modelContext.insert(asset)
        }
        if let error = safeSave(modelContext) {
            saveError = error
        } else {
            dismiss()
        }
    }
}
