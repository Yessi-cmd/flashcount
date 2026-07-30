import Foundation

/// 历史日常消费的三种可解释节奏。
enum CashFlowForecastScenario: String, CaseIterable, Identifiable {
    case lighterSpending
    case typical
    case higherSpending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lighterSpending: return "较低支出"
        case .typical: return "典型节奏"
        case .higherSpending: return "较高支出"
        }
    }
}
