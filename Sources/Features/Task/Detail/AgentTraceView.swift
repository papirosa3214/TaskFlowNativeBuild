import SwiftUI

/// SwiftUI-адаптация Agent Trace: шкала событий и просмотр сохранённых снимков.
struct AgentTraceView: View {
    let taskID: String
    let subtaskID: String?
    @Environment(\.scenePhase) private var scenePhase
    @State private var realtime = RealtimeClient()
    @State private var runs: [AgentTraceRun] = []
    @State private var selectedID: String?
    @State private var position = 1.0
    @State private var followsLive = true
    @State private var loaded = false
    @State private var failed = false
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
                    Button("Сейчас") { selectedID = runs.last?.id; followsLive = true; position = 1 }
                        .foregroundStyle(Color.tfText)
                        .accessibilityIdentifier("agent-trace-live")
                }
                Slider(value: Binding(get: { position }, set: { position = $0; followsLive = false }), in: 0...1)
                    .tint(Color.tfText)
                    .accessibilityLabel("Время просмотра")
                    .accessibilityIdentifier("agent-trace-scrubber")
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(run.spans) { span in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .top) {
                                    Text(span.label).font(.caption).lineLimit(2)
                                    Spacer()
                                    Text(span.state(at: cursor)).font(.caption).foregroundStyle(Color.tfSub)
                                }
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
                                }.frame(height: 8)
                                if span.isEvent { Text("Событие: длительность неизвестна").font(.caption2).foregroundStyle(Color.tfSub) }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("agent-trace-span")
                        }
                        if run.spans.isEmpty { Text("Для этого запуска пока нет действий с временными метками").foregroundStyle(Color.tfSub) }
                    }
                }.frame(maxHeight: 260)
                Text(run.id.hasPrefix("events-") ? "Лента событий: границы запуска неизвестны" : (run.complete ? "Запуск завершён" : "Последний полученный снимок"))
                    .font(.caption).foregroundStyle(Color.tfSub)
            } else if loaded {
                Text(failed ? "Не удалось загрузить ход работы" : "Полученных запусков пока нет").foregroundStyle(Color.tfSub)
            } else { ProgressView() }
            Text("Сохранено на этом устройстве. История содержит полученные события; более ранние действия могут отсутствовать.")
                .font(.caption).foregroundStyle(Color.tfSub)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agent-trace")
        .task(id: scope) {
            #if DEBUG
            if ProcessInfo.processInfo.environment["TASKFLOW_AGENT_TRACE_PREVIEW"] == "1" {
                let start = Date(timeIntervalSince1970: 1791622800)
                runs = [AgentTraceRun(id: "preview", start: start, observedAt: start.addingTimeInterval(30), complete: true, spans: [
                    AgentTraceSpan(id: "read", label: "Чтение проекта", start: start, end: start.addingTimeInterval(8), status: "done"),
                    AgentTraceSpan(id: "test", label: "Проверка результата", start: start.addingTimeInterval(10), end: start.addingTimeInterval(18), status: "error"),
                    AgentTraceSpan(id: "retry", label: "Повторная проверка", start: start.addingTimeInterval(20), end: start.addingTimeInterval(30), status: "done")])]
                selectedID = "preview"; loaded = true
                return
            }
            #endif
            runs = AgentTraceArchive().load(scope: scope); selectedID = runs.last?.id
            guard subtaskID != nil else { loaded = true; return }
            realtime.onEvent = { event in
                if case .taskLive(let live) = event { receive(live) }
            }
            realtime.connect()
        }
        .task(id: "\(scope):\(scenePhase):\(realtime.revision(for: taskID)):\(realtime.activityRevisions[taskID] ?? 0)") {
            #if DEBUG
            if ProcessInfo.processInfo.environment["TASKFLOW_AGENT_TRACE_PREVIEW"] == "1" { return }
            #endif
            guard scenePhase == .active, subtaskID != nil else { return }
            do {
                let live = (try? await APIClient().taskLiveTurns(taskID: taskID)) ?? []
                for turn in live { receive(turn) }
                failed = false
                if live.allSatisfy({ $0.subtaskID != subtaskID }), let subtaskID {
                    let activity = try await APIClient().taskActivity(taskId: taskID).forSubtask(subtaskID)
                    if let start = activity.actions.map(\.date).min() {
                        let events = activity.actions.map { AgentTraceSpan(id: $0.id, label: $0.text ?? "Действие", start: $0.date, end: $0.date, status: "done", isEvent: true) }
                        update(AgentTraceRun(id: "events-" + subtaskID, start: start, observedAt: activity.actions.map(\.date).max() ?? start, complete: false, spans: events))
                    }
                }
            } catch { if !Task.isCancelled { failed = true } }
            loaded = true
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { persist(); realtime.disconnect() } else if subtaskID != nil { realtime.connect() } }
        .onDisappear { persist(); realtime.disconnect(); realtime.onEvent = nil }
    }

    private func receive(_ live: TaskLiveTurn) {
        guard live.taskID == taskID, live.subtaskID == subtaskID, let run = AgentTraceRun.from(live) else { return }
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
