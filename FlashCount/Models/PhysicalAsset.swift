import Foundation
import SwiftData

/// 实物资产类别
enum PhysicalAssetCategory: String, Codable, CaseIterable {
    case phone = "手机"
    case laptop = "笔记本"
    case desktop = "电脑"
    case tablet = "平板"
    case headphone = "耳机"
    case speaker = "音箱"
    case watch = "手表"
    case camera = "相机"
    case console = "游戏机"
    case drone = "无人机"
    case car = "汽车"
    case house = "房产"
    case other = "其他"

    var icon: String {
        switch self {
        case .phone: return "iphone"
        case .laptop: return "laptopcomputer"
        case .desktop: return "desktopcomputer"
        case .tablet: return "ipad"
        case .headphone: return "headphones"
        case .speaker: return "hifispeaker.fill"
        case .watch: return "applewatch"
        case .camera: return "camera.fill"
        case .console: return "gamecontroller.fill"
        case .drone: return "airplane"
        case .car: return "car.fill"
        case .house: return "house.fill"
        case .other: return "cube.fill"
        }
    }

    /// 行业默认年折旧率（第一年）
    var defaultAnnualDepreciationRate: Double {
        switch self {
        case .phone: return 0.25
        case .laptop: return 0.25
        case .desktop: return 0.20
        case .tablet: return 0.20
        case .headphone: return 0.20
        case .speaker: return 0.15
        case .watch: return 0.20
        case .camera: return 0.15
        case .console: return 0.20
        case .drone: return 0.25
        case .car: return 0.20
        case .house: return 0.02
        case .other: return 0.20
        }
    }

    /// 默认预估残值比例
    var defaultSalvageRatio: Double {
        switch self {
        case .phone: return 0.15      // 手机残值约 15%
        case .laptop: return 0.10
        case .desktop: return 0.10
        case .tablet: return 0.15
        case .headphone: return 0.05
        case .speaker: return 0.10
        case .watch: return 0.20
        case .camera: return 0.20
        case .console: return 0.10
        case .drone: return 0.10
        case .car: return 0.30
        case .house: return 0.80
        case .other: return 0.10
        }
    }
}

/// 实物资产（手机、电脑、汽车、房产等）
@Model
final class PhysicalAsset {
    var id: UUID
    var name: String                     // 名称，如 "iPhone 15 Pro"
    var category: PhysicalAssetCategory  // 类别
    var purchasePrice: Decimal           // 购买价格
    var purchaseDate: Date               // 购买日期
    var salvageValue: Decimal            // 预估残值（转手价）
    var targetDailyCost: Decimal         // 目标日成本
    var soldPrice: Decimal?              // 转手价（已出售时）
    var soldDate: Date?                  // 出售日期
    var note: String                     // 备注
    var isArchived: Bool                 // 已归档（已出售）

    init(
        name: String,
        category: PhysicalAssetCategory,
        purchasePrice: Decimal,
        purchaseDate: Date = Date(),
        salvageValue: Decimal? = nil,
        targetDailyCost: Decimal? = nil,
        note: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.category = category
        self.purchasePrice = purchasePrice
        self.purchaseDate = purchaseDate
        // 默认残值 = 购买价 × 行业默认残值比例
        self.salvageValue = salvageValue ?? (purchasePrice * Decimal(category.defaultSalvageRatio))
        // 默认目标日成本 = 折旧成本 ÷ 365
        let depreciableCost = purchasePrice - (salvageValue ?? (purchasePrice * Decimal(category.defaultSalvageRatio)))
        self.targetDailyCost = targetDailyCost ?? (depreciableCost / 365)
        self.note = note
        self.isArchived = false
    }

    // MARK: - 计算属性

    /// 持有天数
    var daysHeld: Int {
        let endDate = soldDate ?? Date()
        return max(1, Calendar.current.dateComponents([.day], from: purchaseDate, to: endDate).day ?? 1)
    }

    /// 可折旧金额 = 购买价 - 残值
    var depreciableCost: Decimal {
        purchasePrice - salvageValue
    }

    /// 当前日均成本 = 可折旧金额 ÷ 持有天数
    var dailyCost: Decimal {
        depreciableCost / Decimal(daysHeld)
    }

    /// 达到目标日成本还需持有天数
    var daysToTarget: Int? {
        guard targetDailyCost > 0 else { return nil }
        let targetDays = NSDecimalNumber(decimal: depreciableCost / targetDailyCost).intValue
        let remaining = targetDays - daysHeld
        return remaining > 0 ? remaining : 0
    }

    /// 回本进度 (0 ~ 1)，达到目标日成本的进度
    var progressToTarget: Double {
        guard targetDailyCost > 0 else { return 0 }
        let targetDays = NSDecimalNumber(decimal: depreciableCost / targetDailyCost).doubleValue
        return min(1.0, Double(daysHeld) / targetDays)
    }

    /// 当前估值 = 购买价 - (日折旧 × 持有天数)，最低为残值
    var currentValue: Decimal {
        let dailyDepreciation = depreciableCost / Decimal(365.0 / Double(category.defaultAnnualDepreciationRate))
        let depreciated = purchasePrice - dailyDepreciation * Decimal(daysHeld)
        return max(salvageValue, depreciated)
    }

    /// 实际收益（已出售时）
    var actualProfit: Decimal? {
        guard let soldPrice else { return nil }
        return soldPrice - purchasePrice
    }

    /// 实际日均成本（已出售时）
    var actualDailyCost: Decimal? {
        guard soldPrice != nil else { return nil }
        return (purchasePrice - (soldPrice ?? 0)) / Decimal(daysHeld)
    }
}
