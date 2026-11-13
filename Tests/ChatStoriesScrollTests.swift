import XCTest

/// Упругость ленты чатов (владелец 13.11.2026): «должна быть упругость…
/// аватарки отбивали поле поиска… а то сопротивление вообще нету и оно
/// улетает всё резко». Быстрый флик не утаскивает ряд ролей и полоску
/// проектов — они возвращаются к поиску; задвигает их только палец,
/// протянувший ряд за порог.
final class ChatStoriesScrollTests: XCTestCase {
    private let row: CGFloat = ChatStoriesTestMetrics.rowHeight
    private let search: CGFloat = ChatStoriesTestMetrics.searchHeight

    private func policy(limit: CGFloat? = nil) -> ChatStoriesScrollPolicy {
        ChatStoriesScrollPolicy(rowHeight: row, searchHeight: search, limit: limit)
    }

    /// Ряд раскрыт, ленту не двигали — остаётся раскрытым.
    @objc func testExpandedStaysExpanded() {
        XCTAssertEqual(policy().target(offset: 0, wasExpanded: true), 0)
    }

    /// Флик из раскрытого: ряд почти не сдвинулся — отбивается назад.
    @objc func testFlingFromExpandedBouncesBack() {
        XCTAssertEqual(policy().target(offset: row * 0.35, wasExpanded: true), 0)
    }

    /// Палец протянул ряд за порог — ряд задвигается.
    @objc func testFingerDragPastThresholdCollapses() {
        XCTAssertEqual(policy().target(offset: row * 0.8, wasExpanded: true), row)
    }

    /// Лента уже спрятана, идёт инерция списка — ряд не раскрывается.
    @objc func testMomentumFromCollapsedDoesNotReopen() {
        XCTAssertEqual(policy().target(offset: row, wasExpanded: false), row)
    }

    /// Поле поиска схлопывается и раскрывается по ближайшему краю.
    @objc func testSearchFieldSnapsBothWays() {
        XCTAssertEqual(policy().target(offset: row + search * 0.3, wasExpanded: false), row)
        XCTAssertEqual(policy().target(offset: row + search * 0.7, wasExpanded: false), row + search)
    }

    /// Потянул ленту вниз — она возвращается на верх.
    @objc func testPulledDownReturnsToTop() {
        XCTAssertEqual(policy().target(offset: -30, wasExpanded: true), 0)
    }

    /// Короткий список дальше схлопнутого поиска не уезжает (правило 12.11.2026).
    @objc func testShortListLimitWins() {
        XCTAssertEqual(policy(limit: row + search).target(offset: row + search + 40, wasExpanded: false),
                       row + search)
    }

    /// Без протяжки палец до половины — по ближайшему краю.
    @objc func testNearestEdgeWithoutDrag() {
        XCTAssertEqual(policy().target(offset: row * 0.3, wasExpanded: false), 0)
        XCTAssertEqual(policy().target(offset: row * 0.6, wasExpanded: false), row)
    }
}

/// Метрики для теста: те же, что в приложении (`ChatStoriesLayout`), но без
/// SwiftUI — файл политики обязан собираться отдельно.
enum ChatStoriesTestMetrics {
    static let rowHeight: CGFloat = 76
    static let searchHeight: CGFloat = 56
}
