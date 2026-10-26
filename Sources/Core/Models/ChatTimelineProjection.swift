import Foundation

/// Порядок ленты чата: сообщения в серверной последовательности, живой ход —
/// сразу после своего якоря.
///
/// Почему отдельный модуль. Раньше живой ход вставлялся в ленту по ДАТЕ
/// начала хода (`firstIndex { $0.date > item.date }`). Дата начала хода не
/// равна моменту фиксации сообщения, поэтому ход мог встать выше более нового
/// сообщения владельца, а при одинаковых датах — произвольно: лента «скакала»
/// (владелец 24.10.2026, карточка 252c400e).
///
/// Правило: сообщения идут в том порядке, в каком их зафиксировал сервер;
/// живой ход вставляется сразу после сообщения-якоря (`trigger_message_id`).
/// Якорь неизвестен (история не загружена) — ход в хвост, и при подгрузке
/// истории порядок не меняется.
public enum ChatTimelineProjection {

    /// Сообщение ленты: идентификатор, текст (для сопоставления с «в пути»)
    /// и признак «своё».
    public struct MessageRef: Equatable, Sendable {
        public let id: String
        public let text: String
        public let isOwn: Bool

        public init(id: String, text: String = "", isOwn: Bool = false) {
            self.id = id
            self.text = text
            self.isOwn = isOwn
        }
    }

    /// Живой ход роли: идентификат проигрывания и якорь — сообщение, на
    /// которое ход начался.
    public struct TurnRef: Equatable, Sendable {
        public let playbackID: String
        public let anchorMessageID: String?

        public init(playbackID: String, anchorMessageID: String? = nil) {
            self.playbackID = playbackID
            self.anchorMessageID = anchorMessageID
        }
    }

    /// Своё сообщение «в пути»: сервер ещё не подтвердил.
    public struct PendingRef: Equatable, Sendable {
        public let id: String
        public let text: String

        public init(id: String, text: String) {
            self.id = id
            self.text = text
        }
    }

    public enum ItemKind: Equatable, Sendable {
        case message
        case liveTurn
        case pending
    }

    /// Строка ленты: что это и по какому идентификатору.
    public struct Item: Equatable, Sendable, Identifiable {
        public let id: String
        public let kind: ItemKind
        public let messageID: String?
        public let turnPlaybackID: String?
        public let pendingID: String?

        public init(id: String, kind: ItemKind, messageID: String? = nil,
                    turnPlaybackID: String? = nil, pendingID: String? = nil) {
            self.id = id
            self.kind = kind
            self.messageID = messageID
            self.turnPlaybackID = turnPlaybackID
            self.pendingID = pendingID
        }
    }

    /// Порядок строк ленты.
    ///
    /// - Parameters:
    ///   - messages: сообщения в серверном порядке (как их отдаёт `sequence`).
    ///   - turns: живые ходы ролей; порядок между собой сохраняется.
    ///   - pending: свои сообщения «в пути».
    public static func project(messages: [MessageRef],
                               turns: [TurnRef],
                               pending: [PendingRef] = []) -> [Item] {
        var items: [Item] = messages.map { message in
            Item(id: "msg:\(message.id)", kind: .message, messageID: message.id)
        }

        // Живой ход — сразу после якоря. Якорь не найден — хвост.
        // Несколько ходов на одном якоре стоят после якоря по порядку ходов.
        var turnsAfterAnchor: [String: Int] = [:]
        var tail: [Item] = []
        for turn in turns {
            let item = Item(id: "turn:\(turn.playbackID)", kind: .liveTurn,
                            turnPlaybackID: turn.playbackID)
            guard let anchor = turn.anchorMessageID,
                  let anchorIndex = items.firstIndex(where: { $0.messageID == anchor }) else {
                tail.append(item)
                continue
            }
            let already = turnsAfterAnchor[anchor] ?? 0
            turnsAfterAnchor[anchor] = already + 1
            items.insert(item, at: anchorIndex + 1 + already)
        }
        items.append(contentsOf: tail)

        // Своё сообщение «в пути»: если сервер уже подтвердил такой же
        // текст, второй раз не показываем (без дубля в ленте).
        let confirmedOwnTexts = Set(messages.filter(\.isOwn).map(\.text))
        for item in pending where !confirmedOwnTexts.contains(item.text) {
            items.append(Item(id: "pending:\(item.id)", kind: .pending, pendingID: item.id))
        }
        return items
    }
}
