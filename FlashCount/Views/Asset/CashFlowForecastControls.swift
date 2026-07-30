import SwiftUI

struct CashFlowForecastControls: View {
    @Binding var horizon: CashFlowForecastHorizon
    @Binding var mode: CashFlowForecastMode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("预测范围")
                .font(.caption.weight(.medium))
                .foregroundStyle(DesignSystem.textSecondary)

            Picker("预测范围", selection: $horizon) {
                ForEach(CashFlowForecastHorizon.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Text("计算口径")
                .font(.caption.weight(.medium))
                .foregroundStyle(DesignSystem.textSecondary)

            Picker("计算口径", selection: $mode) {
                ForEach(CashFlowForecastMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
        }
        .accessibilityIdentifier("cashFlow.controls")
    }
}
