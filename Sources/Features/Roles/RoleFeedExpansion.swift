import Foundation
import Combine

/// Ключ раскрытого блока в ленте: строка ленты + блок внутри неё.
///
/// Ключ собирается из идентификатора строки ленты (`FeedItem.id` — id
/// сообщения или `turn:<playbackID>`, оба живут дольше любого обновления) и
/// идентификатора группы действий (`RoleLiveSegment.identities` — по
/// содержимому, а не по номеру). Версия строки, приход текста в середину хода
/// и переиспользование ячейки ключ не меняют — поэтому раскрытие переживает
/// пересборку строки.
enum RoleFeedExpansionKey {
    /// Раскрытая группа действий в строке ленты.
    static func actions(row: String, group: String) -> String {
        "actions|row:\(row)|group:\(group)"
    }

    /// Раскрытое окошко размышлений в строке ленты.
    static func thinking(row: String, item: String) -> String {
        "thinking|row:\(row)|item:\(item)"
    }

    /// Раскрытый вопрос в карточке обращения роли к роли. Без `|row:`:
    /// id строки ленты у сообщения свой (`feedItemID`), и очистка `retain`
    /// не должна сворачивать карточку.
    static func coordination(message: String) -> String {
        "coordination|message:\(message)"
    }
}

/// Что раскрыто в ленте чата.
///
/// Владелец 11.11.2026: раскрытый блок действий хода «сам сворачивается при
/// прокрутке». Причина — состояние раскрытия жило в `@State` самой строки
/// (`RoleActionGroup`), а лента на `UITableView` строку пересобирает: при
/// обновлении данных версия строки меняется (`ChatFeedVirtualRow.version`),
/// а прокрутка переиспользует ячейку под другую строку. В обоих случаях
/// создаётся новый вид, и `@State` начинается заново со «свёрнуто».
///
/// Поэтому раскрытие живёт здесь, у экрана: одна таблица ключей на комнату,
/// одна версия на все строки. Сами строки только спрашивают «открыто ли» и
/// просят переключить.
@MainActor
final class RoleFeedExpansion: ObservableObject {
    /// Открытые блоки по ключам `RoleFeedExpansionKey`.
    @Published private(set) var expandedKeys: Set<String> = []

    init(expanded: Set<String> = []) {
        expandedKeys = expanded
    }

    func isExpanded(_ key: String) -> Bool { expandedKeys.contains(key) }

    func expand(_ key: String) {
        guard !expandedKeys.contains(key) else { return }
        expandedKeys.insert(key)
    }

    func collapse(_ key: String) {
        guard expandedKeys.contains(key) else { return }
        expandedKeys.remove(key)
    }

    func toggle(_ key: String) {
        if expandedKeys.contains(key) { expandedKeys.remove(key) } else { expandedKeys.insert(key) }
    }

    /// Убрать раскрытия строк, которых больше нет в ленте: иначе таблица
    /// ключей растёт вместе с историей и держит блоки, которые владелец уже
    /// не увидит. Ключи живых строк остаются — в том числе при доигрывании
    /// хода и при смене версии строки.
    func retain(rows: Set<String>) {
        let alive = expandedKeys.filter { key in
            guard let row = Self.row(of: key) else { return true }
            return rows.contains(row)
        }
        guard alive.count != expandedKeys.count else { return }
        expandedKeys = alive
    }

    /// Строка ленты, к которой относится ключ.
    static func row(of key: String) -> String? {
        guard let range = key.range(of: "|row:") else { return nil }
        let rest = key[range.upperBound...]
        guard let end = rest.firstIndex(of: "|") else { return String(rest) }
        return String(rest[..<end])
    }
}
