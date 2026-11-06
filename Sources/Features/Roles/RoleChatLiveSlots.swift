import Foundation

/// «Паспорт» живого хода — то, что нужно ленте, чтобы поставить ход на место:
/// чей ход, какой, когда начался и на какое сообщение отвечает. Текста хода в
/// нём нет: на каждую порцию ответа паспорт не меняется, и экран комнаты не
/// перерисовывается целиком — обновляется только строка хода (владелец
/// 06.11.2026: «вынести живой ход в отдельную вью со своим состоянием»).
///
/// Без моделей чата и без UIKit — проверяется на маке
/// (`Tools/test_role_chat_live_slots.py`).
struct RoleChatLiveSlot: Equatable, Identifiable {
    let userID: String
    let playbackID: String
    let startedAt: String?
    let startDate: Date?
    let triggerMessageID: String?
    /// Есть что показать: элементы хода или размышление.
    let isVisible: Bool

    var id: String { playbackID }
}

enum RoleChatLiveSlots {
    /// Видимые ходы в порядке ленты — как прежний `visibleLiveTurns`: по началу
    /// хода, при равенстве по `playbackID`, ходы без даты — в конце.
    static func visibleSorted(_ slots: [RoleChatLiveSlot]) -> [RoleChatLiveSlot] {
        slots
            .filter(\.isVisible)
            .sorted { ($0.startDate ?? .distantFuture, $0.playbackID) < ($1.startDate ?? .distantFuture, $1.playbackID) }
    }
}
