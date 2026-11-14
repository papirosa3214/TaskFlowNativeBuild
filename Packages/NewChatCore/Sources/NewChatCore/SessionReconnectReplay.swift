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
    /// `carried` — события, пришедшие по сокету, пока ответ на сброс был в
    /// пути. Сервер собрал снимок и окно раньше, чем клиент получил ответ,
    /// поэтому таких событий в `payload.events` нет; без них они пропадали
    /// при замене состояния снимком (ревью `7c7b5da0`, владелец 14.11.2026).
    /// Правило для них то же: та же эпоха и `seq` новее точки снимка — значит,
    /// в записях снимка их быть не может.
    public static func events(
        _ payload: SessionReconnectPayload,
        sessionID: String?,
        carried: [SessionEventEnvelope] = []
    ) -> [SessionEventEnvelope] {
        guard payload.resetRequired, !payload.eventsLost,
              let snapshot = payload.snapshot,
              let point = snapshot.eventPoint else { return [] }
        var seen = Set<String>()
        var fresh: [(seq: Int, event: SessionEventEnvelope)] = []
        for event in payload.events + carried {
            guard event.sessionId == sessionID, seen.insert(event.cursor).inserted else { continue }
            guard let eventPoint = event.eventPoint,
                  eventPoint.epoch == point.epoch,
                  eventPoint.seq > point.seq else { continue }
            fresh.append((eventPoint.seq, event))
        }
        // Порядок ленты: окно ответа и то, что доехало сокетом, перемешиваются
        // по времени, а не по источнику.
        return fresh.sorted { $0.seq < $1.seq }.map(\.event)
    }

    /// Курсор, с которого продолжается догон после сброса. Не откатывается
    /// назад: точка снимка намеренно отстаёт от конца ленты (откат к началу
    /// окна незавершённого ответа), а событие, принятое до сброса, новее неё.
    /// Иначе следующий догон снова просит уже вытесненный кусок, сервер опять
    /// отвечает сбросом (`eventsLost`), и замена состояния с живым ходом
    /// повторяется на каждом переподключении.
    public static func cursor(
        point: SessionEventPoint,
        applied: [SessionEventEnvelope],
        previous: String?
    ) -> String {
        var best = point
        for event in applied {
            guard let eventPoint = event.eventPoint,
                  eventPoint.epoch == point.epoch,
                  eventPoint.seq > best.seq else { continue }
            best = eventPoint
        }
        if let previous, let previousPoint = SessionEventPoint(cursor: previous),
           previousPoint.epoch == point.epoch, previousPoint.seq > best.seq {
            best = previousPoint
        }
        return best.cursor
    }
}
