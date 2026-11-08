import Foundation
import Observation

/// Раздел «Чат» открыт не на главном экране (внутри роли, групповых чатов
/// или поиска). Нижняя панель — только на главных экранах приложения,
/// поэтому внутри раздела её нет (владелец 08.11.2026: «панелька… находятся
/// только на главных экранах; а у меня она до сих пор висит на оркестраторе,
/// поэтому и свайп не работает»).
@Observable
final class ChatSectionState {
    static let shared = ChatSectionState()

    private(set) var isNested = false

    func setNested(_ value: Bool) {
        guard isNested != value else { return }
        isNested = value
    }
}
