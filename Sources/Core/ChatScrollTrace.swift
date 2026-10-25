import Foundation

/// Geometry only: never stores chat IDs, message IDs or message text.
struct ChatScrollGeometry: Codable, Equatable, Sendable {
    let offsetY: Double
    let contentHeight: Double
    let viewportHeight: Double
    let visibleMaxY: Double
}

struct ChatScrollTraceEntry: Codable, Sendable {
    let elapsed: Double
    let geometry: ChatScrollGeometry
    let rowCount: Int
    let duplicateRowCount: Int
    let rowsChanged: Bool
    let liveTurnCount: Int
    let nearBottom: Bool
    let positionedByUser: Bool
}

struct ChatScrollTraceBuffer {
    private(set) var entries: [ChatScrollTraceEntry] = []
    private var previousRows: [String] = []
    @discardableResult
    mutating func append(_ geometry: ChatScrollGeometry, rowIDs: [String], liveTurnCount: Int,
                         nearBottom: Bool, positionedByUser: Bool, at elapsed: Double) -> Bool {
        guard entries.count < 1200,
              entries.last.map({ elapsed - $0.elapsed >= 0.1 }) ?? true else { return false }
        let changed = entries.isEmpty || previousRows != rowIDs
        entries.append(ChatScrollTraceEntry(elapsed: elapsed, geometry: geometry,
            rowCount: rowIDs.count, duplicateRowCount: rowIDs.count - Set(rowIDs).count,
            rowsChanged: changed, liveTurnCount: liveTurnCount,
            nearBottom: nearBottom, positionedByUser: positionedByUser))
        previousRows = rowIDs
        return true
    }
}

/// Passive DEBUG recorder. A serial writer keeps file I/O away from scrolling.
/// One bounded file is replaced atomically; no timer and no observable state.
@MainActor
final class ChatScrollTrace {
    private static let writer = DispatchQueue(label: "taskflow.chat-scroll-trace", qos: .utility)
    private var buffer = ChatScrollTraceBuffer()
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private var lastWrite = -Double.infinity

    func record(_ geometry: ChatScrollGeometry, rowIDs: [String], liveTurnCount: Int,
                nearBottom: Bool, positionedByUser: Bool) {
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        guard buffer.append(geometry, rowIDs: rowIDs, liveTurnCount: liveTurnCount,
                            nearBottom: nearBottom, positionedByUser: positionedByUser, at: elapsed) else { return }
        if elapsed - lastWrite >= 1 || buffer.entries.count == 1200 { flush() }
    }

    func flush() {
        guard !buffer.entries.isEmpty else { return }
        lastWrite = ProcessInfo.processInfo.systemUptime - startedAt
        let entries = buffer.entries
        Self.writer.async {
            do {
                let directory = try FileManager.default.url(for: .applicationSupportDirectory,
                    in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("ChatScrollDiagnostics", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(entries)
                try data.write(to: directory.appendingPathComponent("latest.json"), options: .atomic)
            } catch {
                NSLog("[ChatScrollTrace] could not save geometry: %@", error.localizedDescription)
            }
        }
    }
}
