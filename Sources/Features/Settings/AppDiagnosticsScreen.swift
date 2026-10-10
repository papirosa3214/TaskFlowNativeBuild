import SwiftUI

struct AppDiagnosticsScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot = AppDiagnostics.shared.snapshot()
    @State private var showsReset = false

    var body: some View {
        List {
            Section {
                LabeledContent("Сбор диагностики", value: "Постоянно")
                    .accessibilityElement(children: .combine)
                    .accessibilityValue("Постоянно")
                    .accessibilityIdentifier("diagnostics-collection")
                LabeledContent("Приложение", value: snapshot.background ? "В фоне" : "Открыто")
                Text("Счётчики с \(dateLabel(snapshot.saved.since))")
                    .font(.caption).foregroundStyle(Color.tfSub)
            } footer: {
                Text("Это работа телефона, а не расход батареи в процентах. Работа моделей на сервере сюда не входит.")
            }
            Section("Сейчас") {
                LabeledContent("Очереди текста", value: snapshot.activeQueues == 0 ? "Спят" : "Работают: \(snapshot.activeQueues)")
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(snapshot.activeQueues == 0 ? "Спят" : "Работают: \(snapshot.activeQueues)")
                    .accessibilityIdentifier("diagnostics-queues")
                ForEach(AppDiagnostics.Work.allCases, id: \.rawValue) { work in
                    LabeledContent(work.title, value: String(snapshot.active[work, default: 0]))
                }
            }
            Section("Очередь текста") {
                counter("Такты обработчика", .ticks)
                counter("Обновления текста и действий", .updates)
                counter("Отрисовки потокового текста", .draws)
                counter("Пробуждения", .wakes)
                counter("Засыпания", .sleeps)
            }
            Section("Связь и фон") {
                counter("Сообщения соединений", .messages)
                counter("Переподключения", .reconnects)
                counter("Проверки соединения", .watchdogChecks)
                counter("Запросы к серверу", .requests)
                counter("Получено байт", .bytes)
                counter("События геопозиции", .locationEvents)
            }
            Section {
                counter("Такты очереди в фоне", .ticks, backgroundOnly: true)
                counter("Обновления в фоне", .updates, backgroundOnly: true)
                counter("Отрисовки текста в фоне", .draws, backgroundOnly: true)
                counter("Сообщения в фоне", .messages, backgroundOnly: true)
                counter("Запросы в фоне", .requests, backgroundOnly: true)
                counter("Геопозиция в фоне", .locationEvents, backgroundOnly: true)
            } header: { Text("Когда приложение свёрнуто") }
            footer: { Text("После ухода из чата его очередь должна спать. Соединение и фон островка могут оставаться активными. Когда iOS усыпляет приложение, диагностика тоже не выполняется.") }
            Section("Последние события") {
                ForEach(snapshot.saved.events.reversed()) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.text)
                        Text("\(dateLabel(event.date)) · \(event.background ? "Фон" : "Открыто")")
                            .font(.caption).foregroundStyle(Color.tfSub)
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

    private func counter(_ title: String, _ key: AppDiagnostics.Counter, backgroundOnly: Bool = false) -> some View {
        LabeledContent(title, value: snapshot.count(key, backgroundOnly: backgroundOnly).formatted())
            .accessibilityElement(children: .combine)
            .accessibilityValue(String(snapshot.count(key, backgroundOnly: backgroundOnly)))
            .accessibilityIdentifier("diagnostics-count-" + (backgroundOnly ? "background-" : "") + key.rawValue)
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
