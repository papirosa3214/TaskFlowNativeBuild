import XCTest

/// Иконка в строке текста: низ — на базовой линии, размер — с заглавную букву.
///
/// Владелец 10.11.2026: «иконки неровно отражаются, сделай чтобы на одной
/// линии». Геометрия вынесена в чистую функцию, поэтому проверяется здесь.
final class ChatInlineIconTests: XCTestCase {
    private let ascent: CGFloat = 11.5
    private let descent: CGFloat = 3.5

    @objc func testCanvasCoversLineHeight() {
        let layout = ChatInlineIcon.layout(pointSize: 15, ascent: ascent, descent: descent)
        XCTAssertGreaterThanOrEqual(layout.canvas.height, ascent + descent - 0.001)
    }

    @objc func testIconSitsOnBaseline() {
        let layout = ChatInlineIcon.layout(pointSize: 15, ascent: ascent, descent: descent)
        // Низ иконки — ровно на базовой линии (низ канвы минус высота иконки).
        XCTAssertEqual(layout.icon.maxY, layout.canvas.height, accuracy: 0.001)
        XCTAssertEqual(layout.icon.minY, layout.canvas.height - layout.icon.height, accuracy: 0.001)
    }

    @objc func testIconIsSquare() {
        let layout = ChatInlineIcon.layout(pointSize: 15, ascent: ascent, descent: descent)
        XCTAssertEqual(layout.icon.width, layout.icon.height, accuracy: 0.001)
    }

    @objc func testIconHeightFollowsPointSize() {
        let small = ChatInlineIcon.layout(pointSize: 12, ascent: 9, descent: 3)
        let large = ChatInlineIcon.layout(pointSize: 20, ascent: 15, descent: 5)
        XCTAssertLessThan(small.icon.height, large.icon.height)
    }

    @objc func testIconFitsInsideCanvas() {
        for size in [11, 13, 15, 17, 20] as [CGFloat] {
            let layout = ChatInlineIcon.layout(pointSize: size, ascent: size * 0.76, descent: size * 0.24)
            XCTAssertLessThanOrEqual(layout.icon.maxX, layout.canvas.width + 0.001)
            XCTAssertLessThanOrEqual(layout.icon.maxY, layout.canvas.height + 0.001)
        }
    }
}
