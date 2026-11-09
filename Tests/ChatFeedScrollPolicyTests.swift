import XCTest

/// Лента чата на нативной коллекции: где лента и когда она идёт за низом.
///
/// Владелец 10.11.2026: «давай все же сделаем уже по полной… поведение ленты
/// прям нравится, ноль тупняка, в отличие от моего чата». Ленту ведёт таблица,
/// и её правила прокрутки вынесены в `ChatFeedScrollPolicy`: без них поведение
/// проверялось бы только глазами на телефоне. Проверяем здесь.
final class ChatFeedScrollPolicyTests: XCTestCase {
    @objc func testAtBottomIsNearBottom() {
        let position = ChatFeedScrollPolicy.position(contentHeight: 2000, offset: 1200, viewport: 800)
        XCTAssertTrue(position.isNearBottom)
        XCTAssertEqual(position.distanceToBottom, 0, accuracy: 0.001)
    }

    @objc func testSmallGapIsStillNearBottom() {
        // 79 pt до низа — это «у низа»: ответ печатается, и низ живёт на миг выше.
        let position = ChatFeedScrollPolicy.position(contentHeight: 2000, offset: 1121, viewport: 800)
        XCTAssertTrue(position.isNearBottom)
    }

    @objc func testFarFromBottomIsNotNear() {
        // 81 pt — уже «владелец отлистал»: привязка к низу снимается.
        let position = ChatFeedScrollPolicy.position(contentHeight: 2000, offset: 1119, viewport: 800)
        XCTAssertFalse(position.isNearBottom)
    }

    @objc func testTopOfContentIsNearTop() {
        let position = ChatFeedScrollPolicy.position(contentHeight: 5000, offset: 0, viewport: 800)
        XCTAssertTrue(position.isNearTop)
    }

    @objc func testTopThresholdIsThreeHundred() {
        let edge = ChatFeedScrollPolicy.position(contentHeight: 5000, offset: 300, viewport: 800)
        XCTAssertTrue(edge.isNearTop)
        let past = ChatFeedScrollPolicy.position(contentHeight: 5000, offset: 301, viewport: 800)
        XCTAssertFalse(past.isNearTop)
    }

    @objc func testBottomInsetCountsTowardDistance() {
        // Отступ содержимого внизу — тоже расстояние до низа.
        let position = ChatFeedScrollPolicy.position(contentHeight: 2000, offset: 1000, viewport: 700,
                                                     insetBottom: 100)
        XCTAssertEqual(position.distanceToBottom, 400, accuracy: 0.001)
        XCTAssertFalse(position.isNearBottom)
    }

    @objc func testTopInsetCountsTowardNearTop() {
        let position = ChatFeedScrollPolicy.position(contentHeight: 5000, offset: -100, viewport: 800,
                                                     insetTop: 120)
        // -100 + 120 = 20 pt от верха содержимого — верх рядом.
        XCTAssertTrue(position.isNearTop)
    }

    @objc func testGrowthDoesNotReleaseTheBottom() {
        // Рост ответа двигает геометрию: «на миг не у низа» не повод отпустить
        // низ (владелец 30.10.2026).
        let follows = ChatFeedScrollPolicy.followsBottom(current: true, isNearBottom: false, byUser: false)
        XCTAssertTrue(follows)
    }

    @objc func testOwnerScrollUpReleasesTheBottom() {
        let follows = ChatFeedScrollPolicy.followsBottom(current: true, isNearBottom: false, byUser: true)
        XCTAssertFalse(follows)
    }

    @objc func testOwnerReturnToBottomRestoresIt() {
        let follows = ChatFeedScrollPolicy.followsBottom(current: false, isNearBottom: true, byUser: true)
        XCTAssertTrue(follows)
    }

    @objc func testBottomOffsetIsContentMinusViewport() {
        let offset = ChatFeedScrollPolicy.bottomOffset(contentHeight: 2000, viewport: 800,
                                                       insetTop: 0, insetBottom: 0)
        XCTAssertEqual(offset, 1200, accuracy: 0.001)
    }

    @objc func testBottomOffsetWithInsets() {
        let offset = ChatFeedScrollPolicy.bottomOffset(contentHeight: 2000, viewport: 800,
                                                       insetTop: 12, insetBottom: 16)
        XCTAssertEqual(offset, 1216, accuracy: 0.001)
    }

    @objc func testShortContentStaysAtTopInset() {
        // Содержимое короче экрана: лента стоит на верхнем отступе, а не уезжает
        // в отрицательную бесконечность.
        let offset = ChatFeedScrollPolicy.bottomOffset(contentHeight: 500, viewport: 800,
                                                       insetTop: 20, insetBottom: 0)
        XCTAssertEqual(offset, -20, accuracy: 0.001)
    }
}
