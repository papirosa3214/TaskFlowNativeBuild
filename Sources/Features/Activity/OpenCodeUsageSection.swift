import SwiftUI

/// Расход OpenCode — раздел экрана «Статистика» (владелец 09.11.2026).
///
/// Вёрстка повторяет соседний раздел JEV: те же строки «подпись слева,
/// значение справа», те же линии `TFDivider`, те же ранги шрифтов
/// `.tfText(.row)`/`.tfText(.action)`/`.tfText(.caption)` — без своих
/// размеров и без системных шрифтов.
///
/// Период приходит сверху: полоса периодов одна на весь экран.
struct OpenCodeUsageSection: View {
    /// Период всей статистики: `today`/`week`/`month`.
    let window: String

    @State private var usage: OpenCodeUsage?
    @State private var error: String?
    @State private var modelsExpanded = false
    @Environment(\.scenePhase) private var scenePhase

    private var apiWindow: String {
        switch window {
        case "today": return "today"
        case "month": return "month"
        default: return "week"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text("Расход OpenCode")
                .tfText(.row)
                .foregroundStyle(Color.tfText)
                .frame(maxWidth: .infinity, alignment: .center)

            if let error {
                Text(error).tfText(.caption).foregroundStyle(Color.tfSub)
            }

            if let usage {
                if !usage.available {
                    Text(usage.note).tfText(.action).foregroundStyle(Color.tfSub)
                } else if usage.calls == 0 {
                    TFEmptyState(icon: "chart.bar", text: "За этот период OpenCode ничего не записал.")
                } else {
                    summary(usage)
                    if !usage.models.isEmpty {
                        modelsBlock(usage)
                    }
                    Text(usage.note).tfText(.caption).foregroundStyle(Color.tfDim)
                }
            } else if error == nil {
                TFLoading(.inline)
            }
        }
        .accessibilityIdentifier("opencode-usage.section")
        .task(id: "\(apiWindow):\(scenePhase)") {
            guard scenePhase == .active else { return }
            await load()
        }
    }

    private func summary(_ usage: OpenCodeUsage) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFDivider()
            metric("Вызовы", String(usage.calls))
            metric("Входные токены", AIUsageFormat.tokens(usage.inputTokens))
            metric("Выходные токены", AIUsageFormat.tokens(usage.outputTokens))
            if usage.cacheReadTokens > 0 {
                metric("Из кеша", AIUsageFormat.tokens(usage.cacheReadTokens))
            }
            metric("Стоимость", usage.costText)
            TFDivider()
        }
    }

    private func modelsBlock(_ usage: OpenCodeUsage) -> some View {
        DisclosureGroup(isExpanded: $modelsExpanded) {
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                ForEach(usage.models) { model in
                    VStack(alignment: .leading, spacing: TFSpacing.xs) {
                        Text(model.model).tfText(.row).foregroundStyle(Color.tfText)
                        Text("\(model.provider) · \(AIUsageFormat.tokens(model.totalTokens)) токенов · \(model.calls) вызовов")
                            .tfText(.caption).foregroundStyle(Color.tfSub)
                    }
                    TFDivider()
                }
                if usage.unknownUsageCalls > 0 {
                    Text("Без данных о токенах: \(usage.unknownUsageCalls)")
                        .tfText(.caption).foregroundStyle(Color.tfDim)
                }
            }
            .padding(.top, TFSpacing.sm)
        } label: {
            Text("Подробнее по моделям")
                .tfText(.row)
                .foregroundStyle(Color.tfText)
        }
        .accessibilityIdentifier("opencode-usage.models-toggle")
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
        let requested = apiWindow
        do {
            let value: OpenCodeUsage = try await APIClient().request(
                .get, "/opencode/usage",
                query: [URLQueryItem(name: "window", value: requested)]
            )
            try Task.checkCancellation()
            usage = value
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = usage == nil
                ? "Не удалось загрузить расход OpenCode."
                : "Не удалось обновить расход OpenCode. Показаны предыдущие данные."
        }
    }
}
