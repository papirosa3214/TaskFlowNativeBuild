import SwiftUI
import Charts

struct AIUsageScreen: View {
    @State private var window = "week"
    @State private var usage: AIUsage?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.lg) {
                Picker("Период", selection: $window) {
                    Text("Сегодня").tag("today")
                    Text("7 дней").tag("week")
                    Text("30 дней").tag("month")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("ai-usage.period")
                TFErrorBanner(error, variant: .inline)
                if loading { TFLoading(.block) }
                if let usage {
                    AIUsageSummary(totals: usage.totals)
                    if usage.totals.calls == 0 {
                        TFEmptyState(icon: "chart.bar", text: "За этот период нет сохранённого расхода ролей.")
                    } else {
                        TFSectionHeader("Токены по дням")
                        Chart(usage.daily) { day in
                            BarMark(x: .value("День", String(day.day.suffix(5))),
                                    y: .value("Токены", day.totalTokens))
                        }
                        .frame(height: 150)
                        .accessibilityIdentifier("ai-usage.chart")
                        TFSectionHeader("Модели")
                        ForEach(usage.models) { model in
                            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                                Text(model.model).tfText(.row).foregroundStyle(Color.tfText)
                                Text("\(model.provider) · \(RoleTurnUsageRow.tokens(model.totalTokens)) токенов · \(model.calls) вызовов")
                                    .tfText(.caption).foregroundStyle(Color.tfSub)
                                if let cost = model.estimatedCostUsd {
                                    Text((model.unpricedCalls > 0 ? "Частично: " : "") + RoleTurnUsageRow.cost(cost))
                                        .tfText(.caption).foregroundStyle(Color.tfSub)
                                }
                            }
                            TFDivider()
                        }
                    }
                    Text("Учтены сохранённые ответы моделей ролям TaskFlow. Это не расход всего аккаунта провайдера. Стоимость — тарифная оценка SDK, а не списание с подписки; баланс и стоимость подписки здесь не учитываются.")
                        .tfText(.caption).foregroundStyle(Color.tfSub)
                    if usage.totals.unpricedCalls > 0 {
                        Text("Без данных о цене: \(usage.totals.unpricedCalls) вызовов.")
                            .tfText(.caption).foregroundStyle(Color.tfSub)
                    }
                    if let since = usage.trackingSince, let date = DateFormats.sqliteUTC(since) {
                        Text("Сохранённая история с \(date.formatted(date: .abbreviated, time: .omitted))")
                            .tfText(.caption).foregroundStyle(Color.tfSub)
                    }
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.vertical, TFSpacing.md)
        }
        .background(Color.tfBackground)
        .tfNativeHeader("Статистика", displayMode: .inline)
        .accessibilityIdentifier("ai-usage.screen")
        .hintAnchor(HintAnchorID.aiUsage)
        .task(id: window) { await load() }
        .refreshable { await load() }
    }

    @MainActor private func load() async {
        let selected = window
        loading = true; error = nil; usage = nil
        do {
            let value: AIUsage = try await APIClient().request(.get, "/runtime/usage", query: [URLQueryItem(name: "window", value: selected)])
            guard !Task.isCancelled, selected == window else { return }
            usage = value
        } catch {
            guard !Task.isCancelled, selected == window else { return }
            self.error = error.localizedDescription
        }
        loading = false
    }
}

struct AIUsageSummary: View {
    let totals: AIUsageTotals
    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            metric("Оценка стоимости", totals.costLabel)
                .accessibilityIdentifier("ai-usage.cost")
            metric("Всего токенов", RoleTurnUsageRow.tokens(totals.totalTokens))
            metric("Вход без кэша", RoleTurnUsageRow.tokens(totals.inputTokens))
            metric("Чтение кэша", RoleTurnUsageRow.tokens(totals.cacheReadTokens))
            metric("Выход", RoleTurnUsageRow.tokens(totals.outputTokens))
            metric("Доля кэша во входе", totals.cacheHitRate.map { String(format: "%.1f%%", $0 * 100).replacingOccurrences(of: ".", with: ",") } ?? "Нет данных")
            metric("Вызовов модели", String(totals.calls))
        }
        .accessibilityIdentifier("ai-usage.summary")
    }
    private func metric(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).tfText(.action).foregroundStyle(Color.tfSub)
            Spacer(minLength: TFSpacing.sm)
            Text(value).tfText(.row).foregroundStyle(Color.tfText).monospacedDigit()
        }
    }
}
