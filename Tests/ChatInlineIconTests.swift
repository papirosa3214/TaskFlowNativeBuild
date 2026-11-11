import XCTest

/// Иконка в строке текста: низ — на базовой линии, размер — с заглавную букву.
///
/// Владелец 11.11.2026: «чипы у ссылок соразмерны тексту и не увеличивают
/// высоту строки». Картинка внутри `Text` прижимается низом к базовой линии,
/// поэтому её высота целиком уходит вверх — канва обязана быть не выше
/// подъёма шрифта (`ascent`), иначе строка становится выше обычной.
/// Геометрия вынесена в чистую функцию, поэтому проверяется здесь.
final class ChatInlineIconTests: XCTestCase {
    private let ascent: CGFloat = 11.5
    private let capHeight: CGFloat = 10.5

    /// Строка не растёт: канва иконки не выше подъёма шрифта.
    @objc func testCanvasDoesNotGrowLine() {
        let layout = ChatInlineIcon.layout(pointSize: 15, ascent: ascent, capHeight: capHeight)
        XCTAssertLessThanOrEqual(layout.canvas.height, ascent + 0.001)
    }

    @objc func testIconSitsOnBaseline() {
        let layout = ChatInlineIcon.layout(pointSize: 15, ascent: ascent, capHeight: capHeight)
        // Низ иконки — ровно на базовой линии (низ канвы минус высота иконки).
        XCTAssertEqual(layout.icon.maxY, layout.canvas.height, accuracy: 0.001)
        XCTAssertEqual(layout.icon.minY, layout.canvas.height - layout.icon.height, accuracy: 0.001)
    }

    /// Размер — с заглавную букву соседнего шрифта, не константа.
    @objc func testIconSizeMatchesCapHeight() {
        let layout = ChatInlineIcon.layout(pointSize: 15, ascent: ascent, capHeight: capHeight)
        XCTAssertEqual(layout.icon.height, capHeight, accuracy: 1)
    }

    @objc func testIconIsSquare() {
        let layout = ChatInlineIcon.layout(pointSize: 15, ascent: ascent, capHeight: capHeight)
        XCTAssertEqual(layout.icon.width, layout.icon.height, accuracy: 0.001)
    }

    @objc func testIconHeightFollowsPointSize() {
        let small = ChatInlineIcon.layout(pointSize: 12, ascent: 9, capHeight: 8)
        let large = ChatInlineIcon.layout(pointSize: 20, ascent: 15, capHeight: 14)
        XCTAssertLessThan(small.icon.height, large.icon.height)
    }

    @objc func testIconFitsInsideCanvas() {
        for size in [11, 13, 15, 17, 20] as [CGFloat] {
            let layout = ChatInlineIcon.layout(pointSize: size, ascent: size * 0.76, capHeight: size * 0.7)
            XCTAssertLessThanOrEqual(layout.icon.maxX, layout.canvas.width + 0.001)
            XCTAssertLessThanOrEqual(layout.icon.maxY, layout.canvas.height + 0.001)
        }
    }
}
