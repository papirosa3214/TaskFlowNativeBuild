import XCTest

/// Раскрытый блок действий хода не сворачивается сам.
///
/// Владелец 11.11.2026: раскрыл блок действий роли, начал прокручивать — блок
/// схлопнулся. Причина: раскрытие жило в `@State` строки, а лента на
/// `UITableView` строку пересобирает (версия строки меняется при обновлении
/// данных, ячейка переиспользуется при прокрутке). Раскрытие вынесено в
/// `RoleFeedExpansion` — проверим, что оно переживает эти события.
@MainActor
final class RoleFeedExpansionTests: XCTestCase {
    /// Раскрыли — прокрутили и получили новые данные — блок остался открытым.
    @objc func testExpandedGroupSurvivesRowRebuild() {
        let expansion = RoleFeedExpansion()
        let key = RoleFeedExpansionKey.actions(row: "msg-1", group: "actions:step:read")
        expansion.toggle(key)
        XCTAssertTrue(expansion.isExpanded(key))
        // Пересборка строки (новая версия, другая ячейка) ключ не меняет.
        let again = RoleFeedExpansionKey.actions(row: "msg-1", group: "actions:step:read")
        XCTAssertEqual(key, again)
        XCTAssertTrue(expansion.isExpanded(again), "раскрытие потерялось при пересборке строки")
    }

    /// Приход текста в середину хода не должен закрывать блок: группа
    /// действий в другом месте кода остаётся той же группой.
    @objc func testKeyDoesNotDependOnPosition() {
        let group = "actions:step:edit"
        let before = RoleFeedExpansionKey.actions(row: "turn:p-1", group: group)
        let after = RoleFeedExpansionKey.actions(row: "turn:p-1", group: group)
        XCTAssertEqual(before, after)
        XCTAssertNotEqual(before, RoleFeedExpansionKey.actions(row: "turn:p-2", group: group),
                          "разные ходы не должны делить раскрытие")
    }

    @objc func testToggleAndCollapse() {
        let expansion = RoleFeedExpansion()
        let key = RoleFeedExpansionKey.actions(row: "msg-1", group: "actions:1")
        XCTAssertFalse(expansion.isExpanded(key))
        expansion.toggle(key)
        XCTAssertTrue(expansion.isExpanded(key))
        expansion.toggle(key)
        XCTAssertFalse(expansion.isExpanded(key))
        expansion.expand(key)
        expansion.expand(key)
        XCTAssertTrue(expansion.isExpanded(key))
        expansion.collapse(key)
        XCTAssertFalse(expansion.isExpanded(key))
    }

    /// Раскрытие живёт, пока жива строка: старая история уходит — ключи
    /// убираются, а раскрытая живая строка остаётся при доигрывании хода.
    @objc func testRetainKeepsLiveRowsAndDropsGoneOnes() {
        let expansion = RoleFeedExpansion()
        let live = RoleFeedExpansionKey.actions(row: "turn:p-1", group: "actions:1")
        let gone = RoleFeedExpansionKey.actions(row: "msg-old", group: "actions:1")
        let thinking = RoleFeedExpansionKey.thinking(row: "turn:p-1", item: "thinking:1")
        expansion.expand(live)
        expansion.expand(gone)
        expansion.expand(thinking)
        expansion.retain(rows: ["turn:p-1", "msg-2"])
        XCTAssertTrue(expansion.isExpanded(live), "раскрытие живой строки пропало")
        XCTAssertTrue(expansion.isExpanded(thinking), "раскрытие размышлений живой строки пропало")
        XCTAssertFalse(expansion.isExpanded(gone), "раскрытие исчезнувшей строки осталось")
    }

    @objc func testRowParsing() {
        XCTAssertEqual(RoleFeedExpansion.row(of: RoleFeedExpansionKey.actions(row: "turn:p-1", group: "actions:2")),
                       "turn:p-1")
        XCTAssertEqual(RoleFeedExpansion.row(of: "мусор"), nil)
    }
}
