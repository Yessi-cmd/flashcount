import SwiftUI

private enum DisplayFormatter {
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "¥"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static let decimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static let compactDecimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static let scientific: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .scientific
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM/dd"
        return formatter
    }()

    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年MM月dd日"
        return formatter
    }()

    static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年MM月"
        return formatter
    }()
}

/// 颜色辅助扩展
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

/// 金额格式化
extension Decimal {
    var formattedCurrency: String {
        DisplayFormatter.currency.string(from: self as NSDecimalNumber) ?? "¥0.00"
    }

    var formattedAmount: String {
        DisplayFormatter.decimal.string(from: self as NSDecimalNumber) ?? "0.00"
    }

    /// 用于紧凑列表，防止异常大的金额破坏交易行布局；详情页仍保留完整金额。
    var formattedCompactAmount: String {
        let magnitude = abs(self)
        switch magnitude {
        case ..<10_000:
            return formattedAmount
        case ..<100_000_000:
            return "\(DisplayFormatter.compactDecimal.string(from: (self / 10_000) as NSDecimalNumber) ?? "0")万"
        case ..<10_000_000_000_000_000:
            return "\(DisplayFormatter.compactDecimal.string(from: (self / 100_000_000) as NSDecimalNumber) ?? "0")亿"
        default:
            return DisplayFormatter.scientific.string(from: self as NSDecimalNumber) ?? formattedAmount
        }
    }
}

/// 日期格式化
extension Date {
    var shortDateString: String {
        DisplayFormatter.shortDate.string(from: self)
    }

    var fullDateString: String {
        DisplayFormatter.fullDate.string(from: self)
    }

    var monthYearString: String {
        DisplayFormatter.monthYear.string(from: self)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }

    var relativeString: String {
        if isToday { return "今天" }
        if isYesterday { return "昨天" }
        return shortDateString
    }
}
