import SwiftUI

struct JevUsageSection: View {
    let revision: String
    @State private var window = "24h"
    @State private var usage: JevUsage?
    @State private var error: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section {
            Picker("Период расхода", selection: $window) {
                Text("Сутки").tag("24h")
                Text("Неделя").tag("week")
                Text("Месяц").tag("month")
            }.accessibilityIdentifier("jev-usage.period")
            .foregroundStyle(Color.tfText)
            if let error { Text(error).tfText(.action).foregroundStyle(Color.tfSub) }
            if let usage {
                if !usage.hasKey {
                    Text("Сохраните API-ключ, чтобы видеть его расход в TaskFlow.")
                        .tfText(.body).foregroundStyle(Color.tfSub)
                } else {
                    VStack(alignment: .leading, spacing: TFSpacing.xs) {
                        Text("Запросы: \(usage.calls)").tfText(.body).foregroundStyle(Color.tfText)
                        Text("Успешные / ошибки / в работе: \(usage.succeeded) / \(usage.failed) / \(usage.running)").tfText(.body).foregroundStyle(Color.tfText)
                        Text("Входные токены: \(usage.inputTokens)").tfText(.body).foregroundStyle(Color.tfText)
                        Text("Выходные токены: \(usage.outputTokens)").tfText(.body).foregroundStyle(Color.tfText)
                        Text("Расход в долларах: —").tfText(.body).foregroundStyle(Color.tfText)
                    }
                    Text(usage.coverageText).tfText(.action).foregroundStyle(Color.tfSub)
                    ForEach(usage.scenarios) { scenario in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(scenario.title).tfText(.body).foregroundStyle(Color.tfText)
                            Text("Запросов \(scenario.calls) · вход \(scenario.inputTokens) · выход \(scenario.outputTokens)")
                                .tfText(.action).foregroundStyle(Color.tfSub)
                            if scenario.unknownUsageCalls > 0 {
                                Text("Без данных о токенах: \(scenario.unknownUsageCalls)")
                                    .tfText(.caption).foregroundStyle(Color.tfDim)
                            }
                        }
                    }
                    Text("Учёт с \(ContextObservability.dateText(usage.trackingSince)). Только запросы TaskFlow с текущим ключом и адресом API. Другие приложения в эту сумму не входят.")
                        .tfText(.caption).foregroundStyle(Color.tfDim)
                }
            } else if error == nil { ProgressView("Загрузка расхода…") }
        } header: { Text("Расход в TaskFlow") }
        .tfText(.body).foregroundStyle(Color.tfText)
        .accessibilityIdentifier("jev-usage.section")
        .hintAnchor(HintAnchorID.jevUsage)
        .task(id: "\(window):\(revision):\(scenePhase)") {
            guard scenePhase == .active else { return }
            usage = nil; error = nil
            repeat {
                await load()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            } while !Task.isCancelled
        }
    }
    @MainActor private func load() async {
        do {
            let result: JevUsage = try await APIClient().request(.get, "/jev/usage", query: [URLQueryItem(name: "window", value: window)])
            try Task.checkCancellation()
            usage = result; error = nil
        } catch is CancellationError {} catch {
            self.error = usage == nil ? "Не удалось загрузить расход. Повторяем автоматически." : "Не удалось обновить расход. Показаны предыдущие данные."
        }
    }
}
