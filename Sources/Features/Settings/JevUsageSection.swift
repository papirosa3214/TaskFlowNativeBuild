import SwiftUI

/// Расход JEV в TaskFlow — карточка в стиле пунктов «Настроек».
///
/// Владелец 22.10.2026 (кадр с телефона): «весь текст как-то лесенкой
/// разнобой полностью, ты можешь всё по левому краю выровнять аккуратненько»
/// и «это на фоне ещё дополнительном находится». Было: системные ячейки
/// `List` со своим фоном и каждая строка по центру своей ширины. Стало:
/// одна карточка `TFCard` того же цвета, что и пункты настроек, все строки —
/// в одном `VStack(alignment: .leading)` с прижатым к левому краю текстом.
struct JevUsageSection: View {
    let revision: String
    @State private var window = "24h"
    @State private var usage: JevUsage?
    @State private var error: String?
    @Environment(\.scenePhase) private var scenePhase

    private var windowTitle: String {
        switch window {
        case "week": "Неделя"
        case "month": "Месяц"
        default: "Сутки"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Расход в TaskFlow")
            TFCard {
                VStack(alignment: .leading, spacing: TFSpacing.md) {
                    HStack(spacing: TFSpacing.sm) {
                        Text("Период расхода")
                            .tfText(.body).foregroundStyle(Color.tfText)
                        Spacer(minLength: 0)
                        Picker("Период расхода", selection: $window) {
                            Text("Сутки").tag("24h")
                            Text("Неделя").tag("week")
                            Text("Месяц").tag("month")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(Color.tfSub)
                        .accessibilityIdentifier("jev-usage.period")
                    }
                    if let error {
                        Text(error).tfText(.action).foregroundStyle(Color.tfSub)
                    }
                    if let usage {
                        if !usage.hasKey {
                            Text("Сохраните API-ключ, чтобы видеть его расход в TaskFlow.")
                                .tfText(.body).foregroundStyle(Color.tfSub)
                        } else {
                            usageLines(usage)
                        }
                    } else if error == nil {
                        ProgressView("Загрузка расхода…")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
            }
        }
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

    /// Цифры одной колонкой: одна общая ширина, один левый край. Никаких
    /// отдельных строк-ячеек — иначе каждая строка снова центрируется сама.
    @ViewBuilder
    private func usageLines(_ usage: JevUsage) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Text("Запросы: \(usage.calls)")
            Text("Успешные / ошибки / в работе: \(usage.succeeded) / \(usage.failed) / \(usage.running)")
            Text("Входные токены: \(usage.inputTokens)")
            Text("Выходные токены: \(usage.outputTokens)")
            Text("Расход в долларах: —")
        }
        .tfText(.body)
        .foregroundStyle(Color.tfText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)

        Text(usage.coverageText)
            .tfText(.action).foregroundStyle(Color.tfSub)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)

        ForEach(usage.scenarios) { scenario in
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                Text(scenario.title).tfText(.body).foregroundStyle(Color.tfText)
                Text("Запросов \(scenario.calls) · вход \(scenario.inputTokens) · выход \(scenario.outputTokens)")
                    .tfText(.action).foregroundStyle(Color.tfSub)
                if scenario.unknownUsageCalls > 0 {
                    Text("Без данных о токенах: \(scenario.unknownUsageCalls)")
                        .tfText(.caption).foregroundStyle(Color.tfDim)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
        }

        Text("Учёт с \(ContextObservability.dateText(usage.trackingSince)). Только запросы TaskFlow с текущим ключом и адресом API. Другие приложения в эту сумму не входят.")
            .tfText(.caption).foregroundStyle(Color.tfDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
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
