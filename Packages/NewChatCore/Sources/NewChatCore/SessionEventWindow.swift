import Foundation

/// Окно снимка сессии — метка того, сколько событий легло в состояние.
///
/// Снимок и живые события идут разными путями. Снимок, запрос которого начат
/// при метке `M`, ставится только если метка всё ещё `M`
/// (`SessionSnapshotGate`): иначе в нём может не быть событий, пришедших за
/// время запроса, а `seenCursors` после установки продолжает считать их
/// принятыми — событие пропадает из состояния навсегда.
///
/// Поэтому метку обязаны двигать **все** пути, которые меняют состояние:
///
/// - живые события сокета (`receive`);
/// - догнанные после переподключения (`recoverAfterReconnect`) — раньше они
///   применялись к состоянию и живому ходу напрямую, метку не двигали, и
///   снимок, запрос которого начат раньше, затирал восстановленное;
/// - замена состояния целиком по `resetRequired` — старый снимок старше
///   замены даже тогда, когда новых событий в ответе нет.
///
/// Двигает метку только реально новое событие открытой сессии. Повтор уже
/// принятого куска (его курсор в `seenCursors`) состояние не меняет, а сервер
/// после переподключения пересылает хвост заново: если считать повторы, две
/// попытки установки сгорают на них, и свежий снимок не ставится вовсе.
public struct SessionEventWindow: Equatable, Sendable {
    /// Сколько событий легло в состояние. Растёт только вверх.
    public private(set) var mark: UInt64 = 0

    public init() {}

    /// События догнанного набора, которые состояние ещё не видело: только
    /// открытая сессия и только курсоры вне `seenCursors`, без повторов внутри
    /// набора. Их применяет `recoverAfterReconnect`, их же считает `noteFresh`.
    public static func freshEvents(
        _ events: [SessionEventEnvelope],
        sessionID: String?,
        seenCursors: Set<String>
    ) -> [SessionEventEnvelope] {
        guard let sessionID else { return [] }
        var seen = seenCursors
        var fresh: [SessionEventEnvelope] = []
        for event in events where event.sessionId == sessionID {
            guard seen.insert(event.cursor).inserted else { continue }
            fresh.append(event)
        }
        return fresh
    }

    /// Отметить живое событие сокета. `true` — это событие открытой сессии и
    /// оно новое, то есть легло в состояние.
    @discardableResult
    public mutating func noteLive(
        _ event: SessionEventEnvelope,
        activeSessionID: String?,
        seenCursors: Set<String>
    ) -> Bool {
        guard let activeSessionID, event.sessionId == activeSessionID,
              !seenCursors.contains(event.cursor) else { return false }
        mark &+= 1
        return true
    }

    /// Отметить догнанные события: метка растёт на число реально новых.
    public mutating func noteFresh(_ count: Int) {
        guard count > 0 else { return }
        mark &+= UInt64(count)
    }

    /// Состояние заменено целиком (`resetRequired`, снимок в ответе): любой
    /// снимок, запрос которого начат раньше, старше замены.
    public mutating func noteReset() {
        mark &+= 1
    }
}
