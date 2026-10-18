import SwiftUI

struct AppDiagnosticsScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot = AppDiagnostics.shared.snapshot()
    @State private var showsReset = false

    var body: some View {
        List {
            Section {
                HStack(spacing: TFSpacing.sm) {
                    markIcon(report.mark)
                    Text(report.verdictLine)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("diagnostics-verdict")
                LabeledContent(
                    "Отсчёт",
                    value: "\(DiagnosticsReport.duration(report.intervalMinutes)) · с \(dateLabel(report.startAt))"
                )
                LabeledContent("Приложение", value: snapshot.background ? "В фоне" : "Открыто")
                LabeledContent("Сбор диагностики", value: "Постоянно")
                    .accessibilityElement(children: .combine)
                    .accessibilityValue("Постоянно")
                    .accessibilityIdentifier("diagnostics-collection")
                Text("Счётчики копятся с \(dateLabel(report.countersSince))")
                    .tfText(.meta).foregroundStyle(Color.tfSub)
            } header: {
                Text("Итог")
            } footer: {
                Text("Отсчёт — с того момента, как приложение вернулось на экран (или с запуска): в отчёте видно, сколько стоило то, что вы делали в приложении в этот раз."
                     + " Метки — по скорости роста в минуту: норма, внимание, тревожно. Пороги и откуда они взялись — в DiagnosticsReport.swift."
                     + " Это работа телефона, а не расход батареи в процентах; работа моделей на сервере сюда не входит.")
            }
            Section("Сейчас работает") {
                LabeledContent("Очереди текста", value: snapshot.activeQueues == 0 ? "Спят" : "Работают: \(snapshot.activeQueues)")
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(snapshot.activeQueues == 0 ? "Спят" : "Работают: \(snapshot.activeQueues)")
                    .accessibilityIdentifier("diagnostics-queues")
                ForEach(AppDiagnostics.Work.allCases, id: \.rawValue) { work in
                    LabeledContent(work.title, value: String(snapshot.active[work, default: 0]))
                }
            }
            ForEach(report.groups) { group in
                Section {
                    ForEach(group.rows) { row in counterRow(row) }
                } header: {
                    HStack(spacing: TFSpacing.sm) {
                        Text(group.title)
                        Spacer(minLength: TFSpacing.sm)
                        Text(group.mark.title).foregroundStyle(markColor(group.mark))
                    }
                }
            }
            Section("Последние события") {
                ForEach(snapshot.saved.events.reversed()) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.text)
                        Text("\(dateLabel(event.date)) · \(event.background ? "Фон" : "Открыто")")
                            .tfText(.meta).foregroundStyle(Color.tfSub)
                    }
                }
            }
            Section {
                ShareLink(item: AppDiagnostics.shared.report()) {
                    Label("Поделиться диагностикой", systemImage: "square.and.arrow.up")
                        .foregroundStyle(Color.tfText)
                }
                Button("Сбросить счётчики") { showsReset = true }
                    .foregroundStyle(Color.tfText)
                    .accessibilityIdentifier("diagnostics-reset")
            }
        }
        .foregroundStyle(Color.tfText)
        .tint(Color.tfText)
        .tfScreenBackground()
        .tfNativeHeader("Диагностика")
        .accessibilityIdentifier("app-diagnostics-screen")
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            // Only the open diagnostics page refreshes; collection itself has no timer.
            while !Task.isCancelled {
                snapshot = AppDiagnostics.shared.snapshot()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .onDisappear { AppDiagnostics.shared.checkpoint() }
        .confirmationDialog("Сбросить счётчики диагностики?", isPresented: $showsReset, titleVisibility: .visible) {
            Button("Сбросить", role: .destructive) {
                AppDiagnostics.shared.reset()
                snapshot = AppDiagnostics.shared.snapshot()
            }
        }
    }

    private var report: DiagnosticsReport { DiagnosticsReport(snapshot: snapshot) }

    /// Строка счётчика: сколько всего, сколько прибавилось за отсчёт, с какой
    /// скоростью и что об этом думает метка (владелец 18.10.2026).
    private func counterRow(_ row: DiagnosticsReport.Row) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            HStack(spacing: TFSpacing.sm) {
                markIcon(row.mark)
                Text(row.title)
                Spacer(minLength: TFSpacing.sm)
                Text(DiagnosticsReport.value(row.total, isBytes: row.isBytes))
                    .foregroundStyle(Color.tfSub)
            }
            Text(detail(row))
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(row.mark.title). \(detail(row))")
        .accessibilityIdentifier("diagnostics-count-" + row.id)
    }

    private func detail(_ row: DiagnosticsReport.Row) -> String {
        var parts = [
            DiagnosticsReport.deltaText(row.delta, isBytes: row.isBytes) + " за отсчёт",
            DiagnosticsReport.rateText(row.perMinute, isBytes: row.isBytes),
            "норма до " + DiagnosticsReport.rateText(row.normalLimit, isBytes: row.isBytes),
        ]
        if row.backgroundDelta > 0 {
            parts.append("в фоне " + DiagnosticsReport.deltaText(row.backgroundDelta, isBytes: row.isBytes))
        }
        return parts.joined(separator: " · ")
    }

    private func markIcon(_ mark: DiagnosticsMark) -> some View {
        Image(systemName: mark.symbol)
            .foregroundStyle(markColor(mark))
    }

    private func markColor(_ mark: DiagnosticsMark) -> Color {
        switch mark {
        case .ok: Color.tfGreen
        case .attention: Color.tfOrange
        case .alarm: Color.tfRed
        }
    }

    private func dateLabel(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(Locale(identifier: "ru_RU")))
    }
}

#if DEBUG
/// Exercises real pacer instrumentation and the real settings entry without a server/model.
struct AppDiagnosticsPreview: View {
    var body: some View {
        NavigationStack {
            ServerSettingsScreen()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink("Поток") { AppDiagnosticsStreamPreview() }
                            .accessibilityIdentifier("diagnostics-preview-stream")
                    }
                }
        }
    }
}

private struct AppDiagnosticsStreamPreview: View {
    @State private var complete = false
    var body: some View {
        ScrollView {
            RoleLiveTurnBubble(
                turn: RoleChatLiveTurn(chatID: "diagnostics", userID: "preview", name: "Проверка",
                    startedAt: nil, items: [.text(String(repeating: "Плавный текст проверяет работу очереди. ", count: 12))], thinking: nil),
                showsName: false, isComplete: true, onPlaybackComplete: { complete = true })
                .padding()
            if complete { Text("Поток завершён").accessibilityIdentifier("diagnostics-preview-complete") }
        }
        .navigationTitle("Проверка потока")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
