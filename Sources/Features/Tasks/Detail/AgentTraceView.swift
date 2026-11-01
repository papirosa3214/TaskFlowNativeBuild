import SwiftUI

/// SwiftUI-адаптация Agent Trace: шкала событий и просмотр сохранённых снимков.
struct AgentTraceView: View {
    let taskID: String
    let subtaskID: String?
    @Environment(\.scenePhase) private var scenePhase
    /// Общий канал приложения: свой сокет на каждый экран шторки роли давал
    /// десятки переподключений в минуту (видно в журнале сервера).
    @Environment(RealtimeClient.self) private var realtime
    @State private var observerID: UUID?
    @State private var runs: [AgentTraceRun] = []
    @State private var selectedID: String?
    @State private var position = 1.0
    @State private var followsLive = true
    @State private var loaded = false
    @State private var failed = false
    @State private var scrollRequest = 0
    /// Лента действий протухает от событий активности и обновляется циклом
    /// ниже — не чаще раза в две секунды.
    @State private var refreshState = LiveActivityRefreshState()
    /// Живой ход по сокету уже пришёл — тогда ленту действий REST не догоняет.
    @State private var hasLiveTurn = false
    private var scope: String { taskID + ":" + (subtaskID ?? "none") }
    private var selected: AgentTraceRun? { runs.first { $0.id == selectedID } ?? runs.last }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let run = selected {
                Picker("Запуск / события", selection: Binding(get: { selectedID ?? run.id }, set: {
                    selectedID = $0; followsLive = false; position = 1
                })) {
                    ForEach(runs) { run in Text(run.start.formatted(date: .abbreviated, time: .shortened)).tag(run.id) }
                }
                .accessibilityIdentifier("agent-trace-run")
                let duration = max(1, run.end.timeIntervalSince(run.start))
                let cursor = run.start.addingTimeInterval(duration * position)
                HStack {
                    Text("\(Int(duration * position)) с / \(Int(duration)) с").monospacedDigit()
                    Spacer()
                    Button("Сейчас") { selectedID = runs.last?.id; followsLive = true; position = 1; scrollRequest += 1 }
                        .foregroundStyle(Color.tfText)
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("agent-trace-live")
                }
                Slider(value: Binding(get: { position }, set: { position = $0; followsLive = false }), in: 0...1)
                    .tint(Color.tfText)
                    .accessibilityLabel("Время просмотра")
                    .accessibilityIdentifier("agent-trace-scrubber")
                #if DEBUG
                if ProcessInfo.processInfo.environment["TASKFLOW_AGENT_TRACE_LONG"] == "1" {
                    Button("Следующее действие") {
                        var next = run
                        next.spans.append(AgentTraceSpan(id: "incoming", label: "edit", start: run.end, end: nil, status: "running"))
                        next.observedAt = run.end.addingTimeInterval(1)
                        update(next)
                    }.buttonStyle(.borderless).accessibilityIdentifier("agent-trace-next-preview")
                }
                #endif
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(run.spans) { span in
                                HStack(spacing: 8) {
                                    Label(shortLabel(span), systemImage: symbol(span))
                                        .tfText(.meta).lineLimit(1)
                                        .frame(width: 94, alignment: .leading)
                                    durationBar(span, run: run, cursor: cursor, duration: duration)
                                        .frame(height: 8)
                                    Text(span.state(at: cursor))
                                        .tfText(.caption).foregroundStyle(Color.tfSub)
                                        .frame(width: 50, alignment: .trailing)
                                }
                                .frame(minHeight: 24)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(shortLabel(span)), \(span.state(at: cursor))")
                                .accessibilityValue(span.isEvent ? "Событие: длительность неизвестна" : span.label)
                                .accessibilityIdentifier("agent-trace-span-" + span.id)
                            }
                            if run.spans.isEmpty { Text("Для этого запуска пока нет действий с временными метками").foregroundStyle(Color.tfSub) }
                            Color.clear.frame(height: 1).id("trace-bottom")
                        }
                    }
                    .frame(maxHeight: 260)
                    .defaultScrollAnchor(.bottom)
                    .accessibilityIdentifier("agent-trace-scroll")
                    .onAppear { if followsLive { proxy.scrollTo("trace-bottom", anchor: .bottom) } }
                    .onChange(of: run) { _, _ in
                        if followsLive { proxy.scrollTo("trace-bottom", anchor: .bottom) }
                    }
                    .onChange(of: scrollRequest) { _, _ in proxy.scrollTo("trace-bottom", anchor: .bottom) }
                    .onChange(of: followsLive) { _, follows in
                        if follows { proxy.scrollTo("trace-bottom", anchor: .bottom) }
                    }
                }
                Text(run.id.hasPrefix("events-") ? "Лента событий: границы запуска неизвестны" : (run.complete ? "Запуск завершён" : "Последний полученный снимок"))
                    .tfText(.meta).foregroundStyle(Color.tfSub)
            } else if loaded {
                Text(failed ? "Не удалось загрузить ход работы" : "Полученных запусков пока нет").foregroundStyle(Color.tfSub)
            } else { TFLoading(.inline) }
            Text("Сохранено на этом устройстве. История содержит полученные события; более ранние действия могут отсутствовать.")
                .tfText(.meta).foregroundStyle(Color.tfSub)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agent-trace")
        .task(id: scope) {
            #if DEBUG
            if ProcessInfo.processInfo.environment["TASKFLOW_AGENT_TRACE_PREVIEW"] == "1" {
                let start = Date(timeIntervalSince1970: 1791622800)
                if ProcessInfo.processInfo.environment["TASKFLOW_AGENT_TRACE_LONG"] == "1" {
                    let spans = (0..<24).map { index in
                        AgentTraceSpan(id: "preview-\(index)", label: index.isMultiple(of: 2) ? "read" : "bash",
                            start: start.addingTimeInterval(Double(index)),
                            end: start.addingTimeInterval(Double(index + 1)), status: "done")
                    }
                    runs = [AgentTraceRun(id: "preview", start: start, observedAt: start.addingTimeInterval(24), complete: false, spans: spans)]
                    selectedID = "preview"; loaded = true
                } else {
                    runs = [AgentTraceRun(id: "preview", start: start, observedAt: start.addingTimeInterval(30), complete: true, spans: [
                        AgentTraceSpan(id: "read", label: "read", start: start, end: start.addingTimeInterval(8), status: "done"),
                        AgentTraceSpan(id: "test", label: "bash", start: start.addingTimeInterval(10), end: start.addingTimeInterval(18), status: "error"),
                        AgentTraceSpan(id: "retry", label: "bash", start: start.addingTimeInterval(20), end: start.addingTimeInterval(30), status: "done")])]
                    selectedID = "preview"; loaded = true
                }
                return
            }
            #endif
            runs = AgentTraceArchive().load(scope: scope); selectedID = runs.last?.id
            guard subtaskID != nil else { loaded = true; return }
            // Подписка на общий канал: слот `onEvent` у клиента один, и его
            // держит приложение (TaskStore) — свой слот занял бы его.
            if let observerID { realtime.removeObserver(observerID) }
            observerID = realtime.addObserver { event in
                if case .taskLive(let live) = event { receive(live) }
                // Событие активности само ничего не перерисовывает: ленту
                // забирает цикл ниже, не чаще раза в две секунды.
                if case .taskActivity(let id, _) = event, id == taskID { refreshState.markDirty() }
            }
        }
        // Снимок живого хода — при открытии, смене шага или сцены. Раньше id
        // включал ревизии живых событий, и задача перезапускалась на КАЖДОЕ
        // событие: при идущем ходе это раз в секунду — запрос и перерисовка
        // ленты (владелец 25.10.2026).
        .task(id: "\(scope):\(scenePhase)") {
            #if DEBUG
            if ProcessInfo.processInfo.environment["TASKFLOW_AGENT_TRACE_PREVIEW"] == "1" { return }
            #endif
            guard scenePhase == .active, subtaskID != nil else { return }
            do {
                let live = (try? await APIClient().taskLiveTurns(taskID: taskID)) ?? []
                for turn in live { receive(turn) }
                failed = false
            } catch { if !Task.isCancelled { failed = true } }
            loaded = true
        }
        // Лента действий — по событиям активности, но не чаще раза в две секунды.
        .task(id: "\(scope):\(scenePhase):activity") {
            guard scenePhase == .active, subtaskID != nil else { return }
            await refreshActivityLoop()
        }
        // Сокет общий — его держит приложение; экран только подписан.
        .onChange(of: scenePhase) { _, phase in if phase != .active { persist() } }
        .onDisappear {
            persist()
            if let observerID { realtime.removeObserver(observerID) }
            observerID = nil
        }
    }

    private func presentation(_ span: AgentTraceSpan) -> RoleActionPresentation {
        RoleActionPresentation.forStep(RoleChatLiveStep(id: span.id, tool: span.label, detail: span.detail,
            status: RoleChatLiveStep.Status(rawValue: span.status) ?? .running, resultReceived: span.resultReceived))
    }

    private func shortLabel(_ span: AgentTraceSpan) -> String {
        span.label == "Размышление" ? "Мысль" : presentation(span).title
    }

    private func symbol(_ span: AgentTraceSpan) -> String {
        span.label == "Размышление" ? "brain" : presentation(span).symbol
    }

    private func durationBar(_ span: AgentTraceSpan, run: AgentTraceRun, cursor: Date, duration: Double) -> some View {
        GeometryReader { geometry in
            let offset = min(max(0, 1 - 3 / max(1, geometry.size.width)), max(0, span.start.timeIntervalSince(run.start) / duration))
            let stop = min(span.end ?? run.end, cursor)
            let width = max(0, stop.timeIntervalSince(span.start) / duration)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.tfCard2)
                if cursor >= span.start {
                    Capsule().fill(span.status == "error" && span.end.map { cursor >= $0 } == true ? Color.tfRed : Color.tfText.opacity(0.75))
                        .frame(width: min(geometry.size.width * (1 - offset), max(3, geometry.size.width * width)))
                        .offset(x: geometry.size.width * offset)
                }
                Rectangle().fill(Color.tfSub).frame(width: 1).offset(x: geometry.size.width * position)
            }
        }
        .accessibilityHidden(true)
    }

    /// Цикл обновления ленты действий: ждёт интервал, забирает протухшее
    /// состояние и обновляет список. Пока событий нет — запросов нет.
    private func refreshActivityLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: LiveActivityRefreshState.minimumInterval)
            guard !Task.isCancelled, let subtaskID else { return }
            guard refreshState.takeDirty() else { continue }
            // Живой ход по сокету уже есть — тогда ленту действий REST не догоняет.
            guard !hasLiveTurn else { continue }
            await reloadActivityEvents(subtaskID: subtaskID)
        }
    }

    /// Лента действий без живого хода: события как отдельные отрезки.
    private func reloadActivityEvents(subtaskID: String) async {
        do {
            let activity = try await APIClient().taskActivity(taskId: taskID).forSubtask(subtaskID)
            if let start = activity.actions.map(\.date).min() {
                let events = activity.actions.map { AgentTraceSpan(id: $0.id, label: $0.text ?? "Действие", start: $0.date, end: $0.date, status: "done", isEvent: true) }
                update(AgentTraceRun(id: "events-" + subtaskID, start: start, observedAt: activity.actions.map(\.date).max() ?? start, complete: false, spans: events))
            }
        } catch { if !Task.isCancelled { failed = true } }
    }

    private func receive(_ live: TaskLiveTurn) {
        guard live.taskID == taskID, live.subtaskID == subtaskID, let run = AgentTraceRun.from(live) else { return }
        hasLiveTurn = true
        update(run)
        if live.complete { persist() }
    }
    private func update(_ run: AgentTraceRun) {
        if let index = runs.firstIndex(where: { $0.id == run.id }) { runs[index].merge(run) }
        else { runs.append(run); runs.sort { $0.start < $1.start }; runs = Array(runs.suffix(10)) }
        if followsLive { selectedID = runs.last?.id; position = 1 }
    }
    private func persist() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TASKFLOW_AGENT_TRACE_PREVIEW"] == "1" { return }
        #endif
        AgentTraceArchive().save(runs, scope: scope)
    }
}
