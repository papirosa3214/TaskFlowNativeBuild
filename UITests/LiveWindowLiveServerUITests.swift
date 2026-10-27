import XCTest

/// Временная проверка на живом сервере: окно живого хода в шторке роли не
/// должно сбрасывать прокрутку, пока ход обновляется.
///
/// Владелец 25.10.2026: раздел «работает» обновлялся раз в секунду и уводил
/// окно наверх — долистать до кнопки «Прервать» было невозможно.
final class LiveWindowLiveServerUITests: XCTestCase {
    func testScrollKeepsPositionOnLiveServer() throws {
        continueAfterFailure = false
        let taskID = try String(contentsOfFile: "/tmp/tf-live-taskid", encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let token = try String(contentsOfFile: "/tmp/tf-live-token", encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_TEST_API_URL"] = "http://127.0.0.1:3307"
        app.launchEnvironment["TASKFLOW_DEBUG_TOKEN"] = token
        app.launch()

        // Граф плана командной работы — на табе «План».
        let tab = app.tabBars.buttons["План"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), app.debugDescription)
        tab.tap()

        // Узел роли в графе плана.
        let node = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'plan-node-'"))
            .firstMatch
        for _ in 0..<8 { if node.exists && node.isHittable { break }; app.swipeUp() }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "live-screen"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(node.waitForExistence(timeout: 15), app.debugDescription)
        node.tap()

        let disclosure = app.descendants(matching: .any)["plan-state-live"].firstMatch
        XCTAssertTrue(disclosure.waitForExistence(timeout: 15), app.debugDescription)
        let window = app.scrollViews["plan-slot-live-window"]
        if !window.exists { disclosure.tap() }
        XCTAssertTrue(window.waitForExistence(timeout: 15), app.debugDescription)

        // Прокручиваем окно и запоминаем, где оказался первый видимый абзац.
        window.swipeUp()
        let texts = app.staticTexts.allElementsBoundByIndex
        guard let marker = texts.first(where: { $0.frame.height > 10 && $0.frame.width > 100 }) else {
            XCTFail("в окне нет текста, который можно отследить")
            return
        }
        let afterScroll = marker.frame.minY
        let scrolled = XCTAttachment(screenshot: app.screenshot())
        scrolled.name = "live-after-scroll"; scrolled.lifetime = .keepAlways; add(scrolled)

        // Ждём обновлений живого хода.
        sleep(8)

        let afterUpdates = marker.frame.minY
        let updated = XCTAttachment(screenshot: app.screenshot())
        updated.name = "live-after-updates"; updated.lifetime = .keepAlways; add(updated)
        print("LIVE_SCROLL after=\(afterScroll) afterUpdates=\(afterUpdates)")

        XCTAssertEqual(
            afterUpdates, afterScroll, accuracy: 60,
            "окно живого хода сбросило прокрутку при обновлении содержимого"
        )
        app.terminate()
    }
}
