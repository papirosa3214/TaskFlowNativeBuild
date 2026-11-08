import SwiftUI

/// Настройки → строка «Подсказки»: одна дверь на собственный экран обучения.
/// Список сценариев переехал в `HintsScreen` (владелец 08.11.2026: «сделай это
/// именно как отдельную страницу, как и все остальные», а не раскрытой
/// портянкой внутри настроек).
struct HintsSettingsSection: View {
    @State private var center = HintCenter.shared

    var body: some View {
        NavigationLink(value: AppRoute.hints) {
            TFListRow(
                icon: "lightbulb", iconStyle: .plain, title: "Подсказки",
                subtitle: center.isEnabled ? "Обучение по экранам" : "Выключены",
                trailing: AnyView(
                    Text(progress)
                        .tfText(.meta)
                        .foregroundStyle(Color.tfSub)
                ),
                titleStyle: .body,
                verticalPadding: TFSpacing.xs,
                chevron: .shown
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.hints")
    }

    private var progress: String {
        "\(center.completed.count)/\(center.scenarios.count)"
    }
}
