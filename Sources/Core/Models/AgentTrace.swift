import Foundation

struct AgentTraceSpan: Codable, Equatable, Identifiable {
    let id: String
    var label: String
    var start: Date
    var end: Date?
    var status: String
    /// Метки времени activity обозначают событие, а не длительность.
    var isEvent: Bool = false
    var detail: String? = nil
    var resultReceived: Bool? = nil

    func state(at date: Date) -> String {
        if date < start { return "Ожидает" }
        if isEvent { return "Событие" }
        guard let end, date >= end else { return "В работе" }
        return status == "error" ? "Ошибка" : "Готово"
    }
}

struct AgentTraceRun: Codable, Equatable, Identifiable {
    let id: String
    var start: Date
    var observedAt: Date
    var complete: Bool
    var spans: [AgentTraceSpan]

    var end: Date { max(start, complete ? (spans.compactMap(\.end).max() ?? observedAt) : observedAt) }

    static func from(_ live: TaskLiveTurn, observedAt: Date = .now) -> Self? {
        var spans: [AgentTraceSpan] = []
        for item in live.turn.items {
            switch item {
            case .step(let step):
                guard let start = RoleChatTime.date(step.startedAt) else { continue }
                spans.append(AgentTraceSpan(id: step.id, label: step.tool, start: start,
                    end: RoleChatTime.date(step.endedAt), status: step.status.rawValue, detail: step.detail, resultReceived: step.resultReceived))
            case .thinking(let thought):
                guard let start = RoleChatTime.date(thought.startedAt) else { continue }
                spans.append(AgentTraceSpan(id: thought.id, label: "Размышление", start: start,
                    end: RoleChatTime.date(thought.endedAt), status: thought.isRunning ? "running" : "done"))
            default: break
            }
        }
        guard let start = live.turn.startDate ?? spans.map(\.start).min() else { return nil }
        return Self(id: live.runID, start: start, observedAt: observedAt, complete: live.complete, spans: spans.sorted { $0.start < $1.start })
    }

    mutating func merge(_ newer: Self) {
        guard newer.id == id else { return }
        var byID = Dictionary(uniqueKeysWithValues: spans.map { ($0.id, $0) })
        for span in newer.spans {
            if let old = byID[span.id], old.end != nil, span.end == nil { continue }
            byID[span.id] = span
        }
        spans = Array(byID.values.sorted { $0.start < $1.start }.suffix(300))
        observedAt = max(observedAt, newer.observedAt)
        complete = complete || newer.complete
    }
}

/// Ограниченный архив полученных снимков; не создаёт фоновых наблюдателей.
struct AgentTraceArchive {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(_ scope: String) -> String { "taskflow.agentTrace." + scope }
    func load(scope: String) -> [AgentTraceRun] {
        guard let data = defaults.data(forKey: key(scope)),
              let runs = try? JSONDecoder().decode([AgentTraceRun].self, from: data) else { return [] }
        return runs
    }
    func save(_ runs: [AgentTraceRun], scope: String) {
        // Ограничение на весь архив, а не только на один шаг.
        let prefix = "taskflow.agentTrace."
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) && $0 != key(scope) }.sorted()
        if keys.count >= 100 { for key in keys.prefix(keys.count - 99) { defaults.removeObject(forKey: key) } }
        let bounded = runs.suffix(10).map { run -> AgentTraceRun in
            var copy = run; copy.spans = Array(run.spans.suffix(300)); return copy
        }
        if let data = try? JSONEncoder().encode(bounded) { defaults.set(data, forKey: key(scope)) }
    }
}
