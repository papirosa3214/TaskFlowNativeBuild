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
    ///
    /// `eventsLost` не запрещает проигрывать события новее точки: этот флаг
    /// говорит о вытесненной голове окна, а не о том, что такое событие уже
    /// в снимке. Поэтому запрет снят для обоих источников (ревью владельца
    /// 14.11.2026: `message_end`/`agent_settled` из сокета терялись).
    /// Вытесненную сервером середину окна догон не восстановит — это честно
    /// сообщает курсор (`cursor(point:applied:previous:complete:)`), а не
    /// повторный запрос от вытесненной точки.
    public static func events(
        _ payload: SessionReconnectPayload,
        sessionID: String?,
        carried: [SessionEventEnvelope] = []
    ) -> [SessionEventEnvelope] {
        guard payload.resetRequired,
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
    ///
    /// `complete` — между точкой снимка и последним проигранным событием нет
    /// дыры, которую можно закрыть повтором (усечённая очередь `carried`).
    /// Тогда курсор остаётся на точке снимка: следующий догон спросит окно
    /// заново и потерянное не пропустит (ревью владельца 14.11.2026).
    ///
    /// `eventsLost` полноту не отменяет: сервер эти данные физически
    /// вытеснил, повтор их не вернёт. Курсор за них идёт вперёд — к точке
    /// снимка, проигранным событиям или прежнему курсору, — и никогда не
    /// откатывается к вытесненной точке: иначе каждый обрыв просил бы её
    /// снова и снова получал сброс (ревью владельца 14.11.2026).
    public static func cursor(
        point: SessionEventPoint,
        applied: [SessionEventEnvelope],
        previous: String?,
        complete: Bool = true
    ) -> String {
        guard complete else { return point.cursor }
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

    /// Что проигрывать в живой ход после сброса. Сохранённый ход (`keepingCurrent`)
    /// уже получил события `carried` в `receive` — повторять их значило бы
    /// задвоить шаги и куски текста, поэтому ему достаются только события
    /// ответа. Пересозданное снимком состояние получает окно целиком, включая
    /// `carried` (ревью владельца 14.11.2026).
    ///
    /// `appliedUpTo` — курсор, до которого живой ход уже показал ленту. Живой
    /// ход наполнялся и до запроса: часть окна HTTP к началу догона уже была
    /// применена к нему по сокету, а при повторе от известной дыры окно
    /// начинается раньше конца показанного. Источника (`carried`) для такого
    /// отсева мало — фильтруем по курсору, а не по тому, откуда пришло
    /// событие (ревью владельца 14.11.2026). Состояние при этом получает окно
    /// целиком: его основа — снимок, и там повтор курсором отсекает редьюсер.
    ///
    /// Отсев по курсору — не восстановление: пропущенную середину (события
    /// не новее показанного курсора) в уже наполненный ход не вставляем,
    /// иначе старый кусок текста встанет после нового и текст откатится назад.
    /// Эта часть честно остаётся дырой (`liveTurnHasGaps`) и доезжает
    /// полным текстом в `message_end` — контракт сервера.
    public static func liveEvents(
        _ payload: SessionReconnectPayload,
        sessionID: String?,
        carried: [SessionEventEnvelope] = [],
        keepingCurrent: Bool,
        appliedUpTo: SessionEventPoint? = nil
    ) -> [SessionEventEnvelope] {
        let window = events(
            payload, sessionID: sessionID, carried: keepingCurrent ? [] : carried
        )
        guard keepingCurrent, let appliedUpTo else { return window }
        return notShownYet(window, appliedUpTo: appliedUpTo)
    }

    /// Отсечь события, которые живой ход уже показал (`appliedUpTo` — курсор
    /// его конца). Нужно и вне сброса: после повтора от известной дыры окно
    /// начинается раньше конца показанного, и без отсева живые куски текста
    /// встали бы в ход вторым разом (ревью владельца 14.11.2026).
    /// Порядок сохраняется: отбрасываем только старое, остальное не
    /// переставляется.
    public static func notShownYet(
        _ events: [SessionEventEnvelope],
        appliedUpTo: SessionEventPoint?
    ) -> [SessionEventEnvelope] {
        guard let appliedUpTo else { return events }
        return events.filter { event in
            // Неразобранный курсор не отсеиваем: лучше повторить событие
            // (редьюсер повторы переживёт), чем потерять новое.
            guard let point = event.eventPoint else { return true }
            guard point.epoch == appliedUpTo.epoch else { return true }
            return point.seq > appliedUpTo.seq
        }
    }

    /// С какого курсора просить следующий догон. Пока известна дыра
    /// (`recovering`), живые события уже увели `lastCursor` вперёд, но
    /// просить нужно от дыры — иначе потерянное окно не восстановится.
    /// Курсор из другой эпохи — чужая лента, к текущей дыре не относится.
    public static func resumeCursor(lastCursor: String?, recovering gap: String?) -> String? {
        guard let lastCursor else { return gap }
        guard let gap,
              let last = SessionEventPoint(cursor: lastCursor),
              let gapPoint = SessionEventPoint(cursor: gap),
              last.epoch == gapPoint.epoch else { return lastCursor }
        return gapPoint.seq < last.seq ? gapPoint.cursor : lastCursor
    }
}
