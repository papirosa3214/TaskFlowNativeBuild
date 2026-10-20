import SwiftUI

struct WeeklySummary: Decodable {
    struct Stats: Decodable {
        let completed_count: Int
        let overdue_count: Int
        let active_count: Int
    }
    let greeting: String
    let accomplishments: [String]
    let missed_or_overdue: [String]
    let next_week_focus: [String]
    let productivity_score: Double
    let stats: Stats
    let generated_at: String
}

struct WeeklySummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var summary: WeeklySummary?
    @State private var busy = true
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                if busy { ProgressView("Загрузка сводки…") }
                // 16.10.2026 (LOCK-UI-DRIFT-KNOWN): системная кнопка в потоке
                // экрана всегда синяя, а в приложении кнопки серые. Текст ошибки
                // — тоже обычным `Text`, без общего баннера.
                if let error {
                    Section {
                        TFErrorBanner(error, variant: .block)
                        TFButton("Повторить", icon: "arrow.clockwise", variant: .secondary) {
                            Task { await load() }
                        }
                    }
                }
                if let summary {
                    Section("Продуктивность · \(Int(summary.productivity_score))%") {
                        // Сводку недели пишет роль — общий рендер ответов
                        // (карточка 19f57bc9), а не сырой `Text`.
                        RoleReplyMarkdown(text: summary.greeting)
                        LabeledContent("Сделано", value: "\(summary.stats.completed_count)")
                        LabeledContent("Просрочено", value: "\(summary.stats.overdue_count)")
                        LabeledContent("В работе", value: "\(summary.stats.active_count)")
                    }
                    items("Главные победы недели", summary.accomplishments)
                    items("Долги и хвосты", summary.missed_or_overdue)
                    items("Фокус на следующую неделю", summary.next_week_focus)
                    Section { Text("Обновлено: " + summary.generated_at).font(.caption).foregroundStyle(Color.tfSub) }
                }
            }
            .navigationTitle("Сводка недели")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button { Task { await load(refresh: true) } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(busy).accessibilityLabel("Обновить сводку")
                }
            }
            .task { await load() }
            .accessibilityIdentifier("overview.weekly-summary.sheet")
        }
    }
    @ViewBuilder private func items(_ title: String, _ values: [String]) -> some View {
        if !values.isEmpty { Section(title) { ForEach(values.indices, id: \.self) { RoleReplyMarkdown(text: values[$0]) } } }
    }
    private func load(refresh: Bool = false) async {
        busy = true; error = nil
        defer { busy = false }
        do {
            summary = try await APIClient().request(refresh ? .post : .get,
                refresh ? "/ai/weekly-summary/refresh" : "/ai/weekly-summary", timeout: 180)
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}
