import SwiftUI
import SwiftData

/// 添加资产/负债账户
struct AddAssetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: AssetType = .bankCard
    @State private var balanceText = ""
    @State private var selectedColor = "#667EEA"

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
                            Text("账户名称").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
                            TextField("例如：招商银行储蓄卡", text: $name)
                                .font(.body).foregroundStyle(.white).padding(12)
                                .background(.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                        }

                        // 类型选择
                        VStack(alignment: .leading, spacing: 8) {
                            Text("账户类型").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
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
                                        .background(type == assetType ? Color(hex: selectedColor).opacity(0.2) : .white.opacity(0.04))
                                        .foregroundStyle(type == assetType ? Color(hex: selectedColor) : .white.opacity(0.5))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                        }

                        // 余额
                        VStack(alignment: .leading, spacing: 8) {
                            Text(type.isLiability ? "欠款金额" : "当前余额").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
                            HStack {
                                Text("¥").font(.title3).foregroundStyle(.white.opacity(0.5))
                                TextField("0.00", text: $balanceText).keyboardType(.decimalPad)
                                    .font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(.white)
                            }
                            .padding(12).background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.smallCornerRadius))
                        }

                        // 颜色
                        VStack(alignment: .leading, spacing: 8) {
                            Text("颜色").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
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
            .navigationTitle("添加账户").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }.foregroundStyle(.white.opacity(0.7))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { saveAsset() }
                        .disabled(name.isEmpty || balanceText.isEmpty)
                        .foregroundStyle(DesignSystem.primaryColor)
                }
            }
        }
    }

    private func saveAsset() {
        guard let balance = Decimal(string: balanceText) else { return }
        let asset = Asset(name: name, type: type, balance: balance, colorHex: selectedColor)
        modelContext.insert(asset); try? modelContext.save(); dismiss()
    }
}
