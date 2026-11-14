import Foundation

/// Точка ленты событий сессии — `<epoch>:<seq>`.
///
/// Сервер (`c90c2c18`, контракт `docs/current/owner-session-snapshot-events.md`)
/// кладёт точку в сам снимок (`eventCursor`, `eventCursorEpoch`,
/// `eventCursorSeq`), а каждый конверт события несёт тот же курсор. Поэтому
/// клиент может отличить то, что в `entries` снимка уже есть, от того, что
/// обязан доиграть событиями, — без догадок о покрытии снимка.
public struct SessionEventPoint: Equatable, Sendable, Comparable {
    public let epoch: String
    public let seq: Int

    public init?(epoch: String?, seq: Int?, cursor: String? = nil) {
        if let epoch, let seq, seq >= 0 {
            self.epoch = epoch
            self.seq = seq
            return
        }
        guard let cursor, let parsed = Self.parse(cursor) else { return nil }
        self = parsed
    }

    public init?(cursor: String) {
        guard let parsed = Self.parse(cursor) else { return nil }
        self = parsed
    }

    /// Формат сервера — `<epoch>:<seq>`; эпоха без двоеточий, номер в конце.
    private static func parse(_ cursor: String) -> SessionEventPoint? {
        guard let at = cursor.lastIndex(of: ":") else { return nil }
        let epoch = String(cursor[..<at])
        let seq = Int(cursor[cursor.index(after: at)...])
        guard let seq, !epoch.isEmpty, seq >= 0 else { return nil }
        return SessionEventPoint(epoch: epoch, seq: seq)
    }

    public static func < (lhs: SessionEventPoint, rhs: SessionEventPoint) -> Bool {
        // Эпохи не сравниваются по величине: разная эпоха — другая лента,
        // её события снимку не принадлежат.
        lhs.epoch == rhs.epoch && lhs.seq < rhs.seq
    }

    /// Курсор в формате сервера — его передаём в `?after=` при следующем догоне.
    public var cursor: String { "\(epoch):\(seq)" }
}

public extension SessionSnapshot {
    /// Точка снимка. `nil` — старый сервер без точки: покрытие снимка
    /// неизвестно, и события из ответа на сброс проигрывать нельзя, иначе
    /// записи задвоятся.
    var eventPoint: SessionEventPoint? {
        SessionEventPoint(epoch: eventCursorEpoch, seq: eventCursorSeq, cursor: eventCursor)
    }
}

public extension SessionEventEnvelope {
    var eventPoint: SessionEventPoint? { SessionEventPoint(cursor: cursor) }
}

/// Что из ответа `GET /api/sessions/:id/events` после сброса доигрывать.
///
/// Сервер сам отдаёт только события новее точки снимка, но клиент не верит
/// этому на слово: контракт обратно совместим, и старый ответ на сброс несёт
/// **все** удержанные события, включая уже вошедшие в снимок. Правило одно:
/// основа — снимок, дальше строго по возрастанию точки при той же эпохе.
public enum SessionReconnectReplay {
    public static func events(
        _ payload: SessionReconnectPayload,
        sessionID: String?
    ) -> [SessionEventEnvelope] {
        guard payload.resetRequired, !payload.eventsLost,
              let snapshot = payload.snapshot,
              let point = snapshot.eventPoint else { return [] }
        var seen = Set<String>()
        var fresh: [SessionEventEnvelope] = []
        for event in payload.events {
            guard event.sessionId == sessionID, seen.insert(event.cursor).inserted else { continue }
            guard let eventPoint = event.eventPoint,
                  eventPoint.epoch == point.epoch,
                  eventPoint.seq > point.seq else { continue }
            fresh.append(event)
        }
        return fresh
    }
}
