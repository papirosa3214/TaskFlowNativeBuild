import SwiftUI

/// Расход JEV («Джеффа») — раздел экрана «Статистика».
///
/// Раньше это была карточка в настройках «Оценщика JEV». Владелец 24.10.2026:
/// «оттуда забери, в статистику отдельным разделом поставь именно расходы
/// Джеффа». Вёрстка — как у остальной статистики: подпись слева, значение
/// справа, того же ранга, моноширинными цифрами, блок между линиями.
struct JevUsageSection: View {
    /// Период задаёт экран статистики: одна полоса периодов на весь экран,
    /// а не две (владелец 24.10.2026). JEV понимает только сутки/неделю/месяц.
    let window: String
    @State private var usage: JevUsage?
    @State private var error: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text("Расход JEV")
                .tfText(.row)
                .foregroundStyle(Color.tfText)
                .frame(maxWidth: .infinity, alignment: .center)

            if let error {
                Text(error).tfText(.caption).foregroundStyle(Color.tfSub)
            }
            if let usage {
                if !usage.hasKey {
                    Text("Сохраните API-ключ, чтобы видеть его расход в TaskFlow.")
                        .tfText(.action).foregroundStyle(Color.tfSub)
                } else {
                    summary(usage)
                    scenarios(usage)
                    Text("Учёт с \(ContextObservability.dateText(usage.trackingSince)). Только запросы TaskFlow с текущим ключом и адресом API. Другие приложения в эту сумму не входят.")
                        .tfText(.caption).foregroundStyle(Color.tfDim)
                }
            } else if error == nil {
                ProgressView("Загрузка расхода…")
            }
        }
        .accessibilityIdentifier("jev-usage.section")
        .hintAnchor(HintAnchorID.jevUsage)
        .task(id: "\(window):\(scenePhase)") {
            guard scenePhase == .active else { return }
            usage = nil; error = nil
            repeat {
                await load()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            } while !Task.isCancelled
        }
    }

    private func summary(_ usage: JevUsage) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFDivider()
            metric("Запросы", String(usage.calls))
            metric("Успешные", String(usage.succeeded))
            metric("Ошибки", String(usage.failed))
            metric("В работе", String(usage.running))
            metric("Входные токены", AIUsageFormat.tokens(usage.inputTokens))
            metric("Выходные токены", AIUsageFormat.tokens(usage.outputTokens))
            TFDivider()
            Text(usage.moneyText).tfText(.caption).foregroundStyle(Color.tfDim)
        }
    }

    private func scenarios(_ usage: JevUsage) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            if !usage.scenarios.isEmpty {
                Text("По сценариям")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
            }
            ForEach(usage.scenarios) { scenario in
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    Text(scenario.title).tfText(.row).foregroundStyle(Color.tfText)
                    Text("Запросов \(scenario.calls) · вход \(AIUsageFormat.tokens(scenario.inputTokens)) · выход \(AIUsageFormat.tokens(scenario.outputTokens))")
                        .tfText(.caption).foregroundStyle(Color.tfSub)
                    if scenario.unknownUsageCalls > 0 {
                        Text("Без данных о токенах: \(scenario.unknownUsageCalls)")
                            .tfText(.caption).foregroundStyle(Color.tfDim)
                    }
                }
                TFDivider()
            }
            Text(usage.coverageText).tfText(.caption).foregroundStyle(Color.tfDim)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.md) {
            Text(label).tfText(.row).foregroundStyle(Color.tfText)
            Spacer(minLength: TFSpacing.sm)
            Text(value)
                .tfText(.row)
                .foregroundStyle(Color.tfText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
