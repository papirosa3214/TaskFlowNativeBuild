import XCTest

/// Прокрутка окна живого хода не должна сбрасываться, пока ход обновляется.
///
/// Владелец 25.10.2026: раздел «работает» в шторке роли обновлялся раз в
/// секунду и уводил окно наверх — долистать до кнопки «Прервать» и остановить
/// зависшего агента было невозможно. Фикстура шлёт события `task:activity`
/// раз в секунду, как это делает сервер во время хода.
final class LiveWindowScrollStabilityUITests: XCTestCase {
    func testScrollKeepsPositionWhileStreamUpdates() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_LINEAR_CARD_DEMO"] = "1"
        app.launchEnvironment["TASKFLOW_DEBUG_TOKEN"] = "fixture"
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "tasksheet:energy"
        app.launch()

        let grabber = app.buttons["Sheet Grabber"]
        XCTAssertTrue(grabber.waitForExistence(timeout: 15), app.debugDescription)
        grabber.swipeUp()
        let section = app.buttons["task-card.energy.section.collaborationPlan"]
        XCTAssertTrue(section.waitForExistence(timeout: 10), app.debugDescription)
        let node = app.buttons["plan-node-builder"]
        if !node.exists { section.tap() }
        for _ in 0..<5 { if node.exists && node.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(node.waitForExistence(timeout: 10), app.debugDescription)
        node.tap()

        let disclosure = app.descendants(matching: .any)["plan-state-live"].firstMatch
        XCTAssertTrue(disclosure.waitForExistence(timeout: 10), app.debugDescription)
        let window = app.scrollViews["plan-slot-live-window"]
        if !window.exists { disclosure.tap() }
        XCTAssertTrue(window.waitForExistence(timeout: 10), app.debugDescription)

        // Маркер — строка внутри окна: по ней видно, куда уехала прокрутка.
        let marker = app.staticTexts
            .containing(NSPredicate(format: "label CONTAINS 'Событие 03:'"))
            .firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 5), app.debugDescription)

        // Прокручиваем окно вниз и запоминаем, где оказался маркер.
        let initial = marker.frame.minY
        window.swipeUp()
        let afterScroll = marker.frame.minY
        print("SCROLL initial=\(initial) after=\(afterScroll)")
        XCTAssertTrue(
            abs(afterScroll - initial) > 20,
            "прокрутка внутри окна не сработала — проверка бессмысленна"
        )
        let scrolled = XCTAttachment(screenshot: app.screenshot())
        scrolled.name = "after-scroll"; scrolled.lifetime = .keepAlways; add(scrolled)

        // Содержимое окна должно обновляться: фикстура меняет его на каждый
        // запрос действий и шлёт task:activity раз в секунду.
        let counter = app.staticTexts
            .containing(NSPredicate(format: "label CONTAINS 'обновлений'"))
            .firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 5), app.debugDescription)
        let beforeUpdates = counter.label

        // Ждём обновлений хода.
        sleep(6)

        let afterUpdates = marker.frame.minY
        let updated = XCTAttachment(screenshot: app.screenshot())
        updated.name = "after-updates"; updated.lifetime = .keepAlways; add(updated)

        XCTAssertNotEqual(
            counter.label, beforeUpdates,
            "окно живого хода перестало обновляться — прокрутка держится, потому что контент замер"
        )
        XCTAssertEqual(
            afterUpdates, afterScroll, accuracy: 60,
            "окно живого хода сбросило прокрутку при обновлении содержимого"
        )
        app.terminate()
    }
}
