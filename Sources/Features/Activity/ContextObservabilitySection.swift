import SwiftUI

struct ContextObservabilitySection: View {
    let window: String
    let openTask: (String) -> Void
    @State private var data: ContextObservability?
    @State private var error: String?
    @State private var expanded = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Контекст и JEV").tfText(.title).foregroundStyle(Color.tfText)
            Text("Энричеры добавляют сведения в задание. JEV отбирает память и навыки, проверяет записи и помогает выбрать план и роли.")
                .tfText(.action).foregroundStyle(Color.tfSub)
            if let error { Text(error).tfText(.action).foregroundStyle(Color.tfSub) }
            if let data {
                Text("Учёт с \(ContextObservability.dateText(data.trackingSince))")
                    .tfText(.caption).foregroundStyle(Color.tfDim)
                ForEach(data.summary) { summary in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(summary.kind == "jev" ? "JEV · " : "")\(summary.title)").tfText(.body).foregroundStyle(Color.tfText)
                        Text("Вызовов \(summary.calls) · выполнено \(summary.succeeded) · пропущено \(summary.skipped) · ошибок \(summary.failed) · в работе \(summary.running)")
                            .tfText(.action).foregroundStyle(Color.tfSub)
                        Text("Время: \(Double(summary.durationMs) / 1000, specifier: "%.2f") с")
                            .tfText(.caption).foregroundStyle(Color.tfDim)
                    }
                }
                if data.events.isEmpty {
                    Text("За выбранный период срабатываний ещё нет.").tfText(.body).foregroundStyle(Color.tfSub)
                        .accessibilityIdentifier("context-observability.empty")
                } else {
                    DisclosureGroup("Последние срабатывания", isExpanded: $expanded) {
                        ForEach(data.events) { event in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(event.outcome).tfText(.body).foregroundStyle(Color.tfText)
                                    if let counts = event.countsText { Text(counts).tfText(.action).foregroundStyle(Color.tfSub) }
                                    Text("\(Double(event.durationMs) / 1000, specifier: "%.2f") с · \(ContextObservability.dateText(event.startedAt))")
                                        .tfText(.caption).foregroundStyle(Color.tfDim)
                                    if let task = event.taskTitle { Text(task).tfText(.action).foregroundStyle(Color.tfSub) }
                                    if let role = event.role { Text("Роль: \(role)").tfText(.action).foregroundStyle(Color.tfSub) }
                                    if let step = event.subtaskId { Text("Шаг: \(step)").tfText(.caption).foregroundStyle(Color.tfDim) }
                                    if let input = event.inputTokens, let output = event.outputTokens {
                                        Text("Токены: вход \(input) · выход \(output)").tfText(.action).foregroundStyle(Color.tfSub)
                                    }
                                    ForEach(Array(event.details.enumerated()), id: \.offset) { _, detail in
                                        Text(detail).tfText(.action).foregroundStyle(Color.tfSub)
                                    }
                                    if let taskId = event.taskId {
                                        TFButton("Открыть задачу", variant: .secondary) { openTask(taskId) }
                                    }
                                }.padding(.vertical, 6)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(event.kind == "jev" ? "JEV · " : "")\(event.title)").tfText(.body).foregroundStyle(Color.tfText)
                                    Text(event.outcome).tfText(.caption).foregroundStyle(Color.tfSub)
                                }
                            }
                        }
                    }
                    .tfText(.body).foregroundStyle(Color.tfText)
                    .accessibilityIdentifier("context-observability.events")
                    Text("Показаны последние \(data.events.count) из журнала, максимум \(data.limit). Сводка охватывает весь выбранный период.")
                        .tfText(.caption).foregroundStyle(Color.tfDim)
                }
            } else if error == nil { TFLoading(.inline) }
        }
        .accessibilityIdentifier("context-observability.section")
        .hintAnchor(HintAnchorID.contextObservability)
        .task(id: "\(window):\(scenePhase)") {
            guard scenePhase == .active else { return }
            data = nil; error = nil
            repeat {
                await load()
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            } while !Task.isCancelled
        }
    }
    @MainActor private func load() async {
        do {
            let result: ContextObservability = try await APIClient().request(.get, "/coordination/context-observability", query: [URLQueryItem(name: "window", value: window)])
            try Task.checkCancellation()
            data = result; error = nil
        } catch is CancellationError {} catch {
            self.error = data == nil ? "Не удалось загрузить журнал контекста. Повторяем автоматически." : "Не удалось обновить журнал. Показаны предыдущие данные."
        }
    }
}
