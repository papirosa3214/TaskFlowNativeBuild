import SwiftUI

/// Настройки → «Подсказки» (владелец 16.10.2026): включить пошаговые
/// подсказки и пройти любой сценарий заново. Строки — те же `TFListRow` и
/// `TFToggle`, что у соседних настроек.
struct HintsSettingsSection: View {
    let dividerInset: CGFloat
    @State private var center = HintCenter.shared

    var body: some View {
        TFListRow(
            icon: "lightbulb", iconStyle: .plain, title: "Подсказки",
            trailing: AnyView(
                TFToggle(isOn: $center.isEnabled)
                    .accessibilityLabel("Подсказки")
                    .accessibilityIdentifier("settings.hints")
            ),
            titleStyle: .action,
            verticalPadding: TFSpacing.xs
        )
        if center.isEnabled {
            ForEach(center.scenarios) { scenario in
                TFDivider(inset: dividerInset)
                Button {
                    center.restart(scenario.id)
                } label: {
                    TFListRow(
                        icon: center.completed.contains(scenario.id) ? "checkmark.circle" : "circle",
                        iconStyle: .plain, title: scenario.title,
                        trailing: AnyView(
                            Text(center.completed.contains(scenario.id) ? "Пройти заново" : "Пройти")
                                .tfText(.meta)
                                .foregroundStyle(Color.tfText)
                        ),
                        titleStyle: .action,
                        verticalPadding: TFSpacing.xs
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.hints.\(scenario.id)")
            }
        }
    }
}
