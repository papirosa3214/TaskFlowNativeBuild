import SwiftUI

/// Настройки → «Подсказки» — отдельный экран, как и все остальные (владелец
/// 08.11.2026): «проваливаюсь в этот раздел подсказки и там уже могу нажимать,
/// и меня будет перебрасывать в то или иное окно, где я прохожу обучение».
///
/// Чипы сценариев остаются: пройденный гаснет сам, любой можно пройти заново,
/// а «Включить все заново» возвращает обучение целиком.
struct HintsScreen: View {
    @State private var center = HintCenter.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.xl) {
                switchRow
                TFSectionHeader("Сценарии", style: .caps)
                scenarioRows
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.top, TFSpacing.md)
            .padding(.bottom, TFSpacing.xl * 2)
        }
        .tfScreenBackground()
        .tfNativeHeader("Подсказки")
    }

    /// Главный выключатель и «включить всё заново» — то же, что было в
    /// настройках строкой, только со своим объяснением.
    @ViewBuilder
    private var switchRow: some View {
        TFCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                TFListRow(
                    icon: "lightbulb", iconStyle: .plain,
                    title: "Показывать подсказки при переходе",
                    subtitle: "Пройденный сценарий гаснет сам",
                    trailing: AnyView(
                        TFToggle(isOn: $center.isEnabled)
                            .accessibilityLabel("Подсказки")
                            .accessibilityIdentifier("hints.enabled")
                    ),
                    titleStyle: .body,
                    verticalPadding: TFSpacing.xs
                )
                TFDivider()
                TFButton("Включить все заново", icon: "arrow.counterclockwise", variant: .secondary) {
                    center.resetAll()
                }
                .padding(TFSpacing.md)
                .accessibilityIdentifier("hints.resetAll")
            }
        }
    }

    @ViewBuilder
    private var scenarioRows: some View {
        TFCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(center.scenarios.enumerated()), id: \.element.id) { index, scenario in
                    if index > 0 { TFDivider() }
                    scenarioRow(scenario)
                }
            }
        }
    }

    @ViewBuilder
    private func scenarioRow(_ scenario: HintScenario) -> some View {
        let passed = center.completed.contains(scenario.id)
        let row = TFListRow(
            icon: passed ? "checkmark.circle" : "circle",
            iconStyle: .plain,
            title: scenario.title,
            subtitle: HintsDestination.title(for: scenario) ?? "Открывается в карточке задачи",
            trailing: AnyView(
                Text(passed ? "Заново" : "Пройти")
                    .tfText(.meta)
                    .foregroundStyle(Color.tfText)
            ),
            titleStyle: .body,
            verticalPadding: TFSpacing.xs
        )
        if let route = HintsDestination.route(for: scenario) {
            NavigationLink(value: route) { row }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { center.restart(scenario.id) })
                .accessibilityIdentifier("settings.hints.\(scenario.id)")
        } else {
            Button { center.restart(scenario.id) } label: { row }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.hints.\(scenario.id)")
        }
    }
}

/// Куда ведёт сценарий: экран берётся по якорю первого шага. Сценарии, которым
/// нужна конкретная карточка или живой чат, маршрута не имеют — их запускают
/// там, где они и происходят.
enum HintsDestination {
    private static let routes: [String: AppRoute] = [
        HintAnchorID.projectsAllTasks: .allTasks,
        HintAnchorID.allTasksFilter: .allTasks,
        HintAnchorID.tasksWorkCards: .allTasks,
        HintAnchorID.webhooksEntry: .integrations,
        HintAnchorID.voiceModes: .secretaryVoicePicker,
        HintAnchorID.jevConnection: .jevSettings,
        HintAnchorID.jevUsage: .jevSettings,
        HintAnchorID.memoryObserver: .memoryObserverSettings,
        HintAnchorID.roleLoadRows: .roleLoad,
        HintAnchorID.agentInstructions: .agents,
        HintAnchorID.roleBehavior: .agents,
        HintAnchorID.aiUsage: .activity,
        HintAnchorID.contextObservability: .activity,
        HintAnchorID.noteMarkdownEditing: .notes,
        HintAnchorID.systemSummary: .notifications,
    ]

    private static let titles: [String: String] = [
        HintAnchorID.projectsAllTasks: "«Все задачи»",
        HintAnchorID.allTasksFilter: "«Все задачи»",
        HintAnchorID.tasksWorkCards: "«Все задачи»",
        HintAnchorID.webhooksEntry: "«Интеграции»",
        HintAnchorID.voiceModes: "«Модели и голоса»",
        HintAnchorID.jevConnection: "«Jev»",
        HintAnchorID.jevUsage: "«Jev»",
        HintAnchorID.memoryObserver: "«Наблюдатель памяти»",
        HintAnchorID.roleLoadRows: "«Загрузка ролей»",
        HintAnchorID.agentInstructions: "«Команда»",
        HintAnchorID.roleBehavior: "«Команда»",
        HintAnchorID.aiUsage: "«Активность»",
        HintAnchorID.contextObservability: "«Активность»",
        HintAnchorID.noteMarkdownEditing: "«Заметки»",
        HintAnchorID.systemSummary: "«Состояние системы»",
    ]

    static func anchor(of scenario: HintScenario) -> String? {
        scenario.steps[scenario.start]?.anchor
    }

    static func route(for scenario: HintScenario) -> AppRoute? {
        guard let anchor = anchor(of: scenario) else { return nil }
        return routes[anchor]
    }

    static func title(for scenario: HintScenario) -> String? {
        guard let anchor = anchor(of: scenario) else { return nil }
        return titles[anchor]
    }
}
