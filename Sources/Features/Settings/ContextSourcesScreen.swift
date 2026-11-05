import SwiftUI

/// Настройки → «Энричеры и модели»: как собирается контекст ролей, на каких моделях
/// и как часто срабатывает. Пока этого не было видно нигде (владелец 05.11.2026).
struct ContextSourcesScreen: View {
    private struct TaskRef: Identifiable { let id: String }

    @State private var window = "24h"
    @State private var selectedTask: TaskRef?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.lg) {
                Picker("Период", selection: $window) {
                    Text("Сутки").tag("24h")
                    Text("3 дня").tag("3d")
                    Text("Неделя").tag("week")
                    Text("Месяц").tag("month")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("context-sources.window")
                ContextObservabilitySection(window: window) { selectedTask = TaskRef(id: $0) }
            }
            .padding(TFSpacing.screenHorizontal)
        }
        .tfScreenBackground()
        .tfNativeHeader("Энричеры и модели", displayMode: .inline)
        .taskCardSheet(item: $selectedTask)
    }
}
