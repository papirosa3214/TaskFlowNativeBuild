import Foundation

/// Очередь установки снимка сессии.
///
/// Снимок и живые события идут разными путями, поэтому здесь решаются два
/// разных дела (владелец, 14.11.2026):
///
/// 1. **Порядок.** Сеть отвечает не по порядку: два параллельных запроса
///    снимка одной сессии завершаются как получится, и раньше более ранний
///    ответ затирал более новый. Установка идёт только по возрастанию номера
///    запроса, ответ с номером не больше уже установленного отбрасывается.
///
/// 2. **Окно запроса.** Сервер не сообщает, до какого события снимок
///    актуален: `GET /api/sessions/:id` отдаёт только записи сессии, ни
///    курсора, ни порядкового номера в ответе нет (`server/src/routes/owner-sessions.ts`,
///    `server/src/runtime/ownerSessionRuntime.ts`). Поэтому снимок, во время
///    запроса которого пришли события, ставить нельзя: их в снимке может не
///    быть, а `seenCursors` после установки продолжает считать их принятыми —
///    событие пропадает из состояния навсегда. Такой снимок отбрасывается.
///
/// Жёсткая гарантия «снимок плюс всё, что после него» без серверной правки
/// невозможна: для неё в ответе нужен курсор, снятый в один момент с чтением
/// записей. Поэтому здесь не додумывается покрытие снимка, а требуется пустое
/// окно.
public struct SessionSnapshotGate: Sendable, Equatable {
    public enum Verdict: Equatable, Sendable {
        /// Ставить: ответ на самый новый запрос, событий за время запроса не было.
        case install
        /// Ответ старше уже установленного снимка — выбросить.
        case superseded
        /// За время запроса пришли события — снимок может быть старше их.
        case windowDirty
    }

    public struct Ticket: Equatable, Sendable {
        public let serial: UInt64
        public let windowMark: UInt64
    }

    private var issued: UInt64 = 0
    private var installed: UInt64 = 0

    public init() {}

    /// Отметка на момент начала запроса: номер запроса и метка окна событий.
    public mutating func begin(windowMark: UInt64) -> Ticket {
        issued &+= 1
        return Ticket(serial: issued, windowMark: windowMark)
    }

    public func verdict(_ ticket: Ticket, windowMark: UInt64) -> Verdict {
        if ticket.serial <= installed { return .superseded }
        if ticket.windowMark != windowMark { return .windowDirty }
        return .install
    }

    public mutating func markInstalled(_ ticket: Ticket) {
        installed = max(installed, ticket.serial)
    }
}
