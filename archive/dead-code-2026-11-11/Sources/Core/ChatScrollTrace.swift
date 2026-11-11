import Foundation

/// Geometry only: never stores chat IDs, message IDs or message text.
struct ChatScrollGeometry: Codable, Equatable, Sendable {
    let offsetY: Double
    let contentHeight: Double
    let viewportHeight: Double
    let visibleMaxY: Double
    /// Горизонталь: лента у роли прижата к левому краю (владелец 27.10.2026) —
    /// различить сдвиг всей ленты вбок и ширину содержимого больше экрана.
    var offsetX: Double = 0
    var contentWidth: Double = 0
    var viewportWidth: Double = 0
}

/// Что происходило вокруг ленты в момент замера (владелец 27.10.2026: лента
/// уезжает вверх, пока набираешь сообщение, — без клавиатуры и фазы прокрутки
/// по одной геометрии этого не отличить).
struct ChatScrollContext: Codable, Equatable, Sendable {
    var keyboardHeight: Double = 0
    var composerFocused = false
    /// Фаза прокрутки: idle — лента стоит сама, а сдвиг в idle — это
    /// программный скачок, не жест.
    var phase = "idle"
}

struct ChatScrollTraceEntry: Codable, Sendable {
    let elapsed: Double
    /// Время на часах телефона: владелец говорит «около 14:32», по нему ищем.
    var wallTime: Double = Date().timeIntervalSince1970
    let geometry: ChatScrollGeometry
    let rowCount: Int
    let duplicateRowCount: Int
    let rowsChanged: Bool
    let liveTurnCount: Int
    let nearBottom: Bool
    let positionedByUser: Bool
    var context = ChatScrollContext()
    /// nil — обычный замер; иначе событие: keyboard, focus, send, phase, rows.
    var event: String?
}

struct ChatScrollTraceBuffer {
    /// Один сеанс экрана; ~10 минут непрерывного движения при 10 замерах/с.
    static let capacity = 6000
    private(set) var entries: [ChatScrollTraceEntry] = []
    private var previousRows: [String] = []
    private var last: ChatScrollTraceEntry?

    @discardableResult
    mutating func append(_ geometry: ChatScrollGeometry, rowIDs: [String], liveTurnCount: Int,
                         nearBottom: Bool, positionedByUser: Bool,
                         context: ChatScrollContext = ChatScrollContext(), at elapsed: Double) -> Bool {
        guard entries.count < Self.capacity,
              entries.last(where: { $0.event == nil }).map({ elapsed - $0.elapsed >= 0.1 }) ?? true else { return false }
        let changed = entries.isEmpty || previousRows != rowIDs
        let entry = ChatScrollTraceEntry(elapsed: elapsed, geometry: geometry,
            rowCount: rowIDs.count, duplicateRowCount: rowIDs.count - Set(rowIDs).count,
            rowsChanged: changed, liveTurnCount: liveTurnCount,
            nearBottom: nearBottom, positionedByUser: positionedByUser, context: context)
        entries.append(entry)
        last = entry
        previousRows = rowIDs
        return true
    }

    /// Событие пишется сразу, без прореживания.
    @discardableResult
    mutating func appendEvent(_ name: String, geometry: ChatScrollGeometry?, context: ChatScrollContext,
                              at elapsed: Double) -> Bool {
        guard entries.count < Self.capacity else { return false }
        entries.append(ChatScrollTraceEntry(elapsed: elapsed,
            geometry: geometry ?? last?.geometry ?? ChatScrollGeometry(offsetY: 0, contentHeight: 0, viewportHeight: 0, visibleMaxY: 0),
            rowCount: last?.rowCount ?? 0, duplicateRowCount: last?.duplicateRowCount ?? 0,
            rowsChanged: false, liveTurnCount: last?.liveTurnCount ?? 0,
            nearBottom: last?.nearBottom ?? false, positionedByUser: last?.positionedByUser ?? false,
            context: context, event: name))
        return true
    }
}

enum ChatScrollTraceFiles {
    static let keep = 40
    /// Старые сеансы сверх `keep` и прежний единственный `latest.json`.
    static func filesToDelete(_ names: [String], keep: Int = keep) -> [String] {
        let sessions = names.filter { $0.hasPrefix("session-") && $0.hasSuffix(".json") }.sorted()
        return names.filter { $0 == "latest.json" } + sessions.dropLast(keep)
    }
}

/// Passive DEBUG recorder. A serial writer keeps file I/O away from scrolling.
/// Каждое открытие чата — свой файл `session-<дата-время>.json`; хранятся
/// последние 40 сеансов, чтобы баги копились днями, пока владелец не скажет «забери».
@MainActor
final class ChatScrollTrace {
    private static let writer = DispatchQueue(label: "taskflow.chat-scroll-trace", qos: .utility)
    private var buffer = ChatScrollTraceBuffer()
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private var lastWrite = -Double.infinity
    private let fileName: String
    private(set) var context = ChatScrollContext()

    init() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        fileName = "session-\(formatter.string(from: Date())).json"
    }

    private var elapsed: Double { ProcessInfo.processInfo.systemUptime - startedAt }

    func record(_ geometry: ChatScrollGeometry, rowIDs: [String], liveTurnCount: Int,
                nearBottom: Bool, positionedByUser: Bool) {
        guard buffer.append(geometry, rowIDs: rowIDs, liveTurnCount: liveTurnCount,
                            nearBottom: nearBottom, positionedByUser: positionedByUser,
                            context: context, at: elapsed) else { return }
        flushIfDue()
    }

    /// Смена клавиатуры, фокуса или фазы — отдельным событием с новым контекстом.
    func update(_ change: (inout ChatScrollContext) -> Void, event: String) {
        var next = context
        change(&next)
        guard next != context else { return }
        context = next
        buffer.appendEvent(event, geometry: nil, context: context, at: elapsed)
        flushIfDue()
    }

    func event(_ name: String) {
        buffer.appendEvent(name, geometry: nil, context: context, at: elapsed)
        flushIfDue()
    }

    private func flushIfDue() {
        if elapsed - lastWrite >= 1 || buffer.entries.count == ChatScrollTraceBuffer.capacity { flush() }
    }

    func flush() {
        guard !buffer.entries.isEmpty else { return }
        lastWrite = elapsed
        let entries = buffer.entries
        let fileName = fileName
        Self.writer.async {
            do {
                let directory = try FileManager.default.url(for: .applicationSupportDirectory,
                    in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("ChatScrollDiagnostics", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(entries)
                try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
                let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                for name in ChatScrollTraceFiles.filesToDelete(names) {
                    try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
                }
            } catch {
                NSLog("[ChatScrollTrace] could not save geometry: %@", error.localizedDescription)
            }
        }
    }
}
