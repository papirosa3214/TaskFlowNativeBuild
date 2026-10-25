import Foundation

/// Прерванный ответ роли (карточка b504958a, доработка D1: уточнение владельца
/// останавливает текущий ход). Сервер отдаёт `stop_reason` — почему ответ
/// прерван, и `partial` — что ответ сохранён частично.
public enum ChatMessageInterruption: Sendable, Equatable {
    /// Владелец прислал уточнение — ход остановлен на середине.
    case ownerInterrupt
    /// Ход упал с ошибкой.
    case failed
    /// Причина названа сервером, но клиенту незнакома.
    case other(String)
    /// Прерывание есть, а причину сервер не назвал.
    case unknown

    /// nil — ответ не прерывали: обычное сообщение в ленте.
    public init?(stopReason: String?, partial: Bool) {
        if stopReason == "owner_interrupt" {
            self = .ownerInterrupt
            return
        }
        if stopReason == "error" {
            self = .failed
            return
        }
        if let reason = stopReason, !reason.isEmpty {
            self = .other(reason)
            return
        }
        if partial {
            self = .unknown
            return
        }
        return nil
    }

    /// Подпись для владельца: почему ответ не дописан.
    public var label: String {
        switch self {
        case .ownerInterrupt: "Ответ прерван уточнением владельца"
        case .failed: "Ответ прерван ошибкой"
        case .other: "Ответ прерван"
        case .unknown: "Ответ прерван"
        }
    }

    /// Прерванный ответ требует внимания владельца.
    public var isProblem: Bool { true }
}