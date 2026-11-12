import XCTest

/// Иконка в строке текста: крупная, как буква с выносными элементами, и
/// по центру строчных букв, а не над ними.
///
/// Владелец 11.11.2026: «ярлычки микроскопические, разобрать с первого раза
/// не получается» и «листик должен начинаться там, где буковка, и стоять
/// ровно, а не выше». Иконка размером с кегль опускается ниже базовой линии
/// (`baselineOffset`), так что её центр совпадает с серединой заглавной буквы.
/// Строку она при этом не раздвигает: верх — не выше подъёма шрифта, низ —
/// не ниже его спуска. Геометрия — чистая функция, поэтому проверяется здесь.
final class ChatInlineIconTests: XCTestCase {
    private let size: CGFloat = 17
    private let ascent: CGFloat = 16.2
    private let descent: CGFloat = 4.1
    private let capHeight: CGFloat = 12

    private var layout: ChatInlineIcon.Layout {
        ChatInlineIcon.layout(pointSize: size, ascent: ascent, descent: descent, capHeight: capHeight)
    }

    /// Крупная: не меньше 85% кегля (была с заглавную букву — 70%).
    @objc func testIconIsLarge() {
        XCTAssertGreaterThanOrEqual(layout.icon.height, size * 0.85)
    }

    /// Центр иконки — на середине заглавной буквы.
    @objc func testIconCenteredOnCapHeight() {
        let center = layout.icon.height / 2 + layout.baselineOffset
        XCTAssertEqual(center, capHeight / 2, accuracy: 0.5)
    }

    /// Строка не растёт ни вверх, ни вниз.
    @objc func testIconStaysInsideLine() {
        XCTAssertLessThanOrEqual(layout.icon.height + layout.baselineOffset, ascent + 0.001)
        XCTAssertGreaterThanOrEqual(layout.baselineOffset, -descent - 0.001)
    }

    @objc func testIconIsSquareAndFillsCanvas() {
        XCTAssertEqual(layout.icon.width, layout.icon.height, accuracy: 0.001)
        XCTAssertEqual(layout.canvas.height, layout.icon.height, accuracy: 0.001)
    }

    @objc func testIconHeightFollowsPointSize() {
        let small = ChatInlineIcon.layout(pointSize: 12, ascent: 11.4, descent: 2.9, capHeight: 8.5)
        let large = ChatInlineIcon.layout(pointSize: 20, ascent: 19, descent: 4.8, capHeight: 14)
        XCTAssertLessThan(small.icon.height, large.icon.height)
    }
}
