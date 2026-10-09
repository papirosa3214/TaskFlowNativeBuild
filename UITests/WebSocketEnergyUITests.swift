import XCTest

final class WebSocketEnergyUITests: XCTestCase {
    private func probe(_ path: String) -> [String: Int] {
        let done = expectation(description: path)
        var counts: [String: Int] = [:]
        URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:3307/probe/" + path)!) { data, _, _ in
            if let data { counts = (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:] }
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 5)
        return counts
    }

    func testCardIsIdleThenUpdatesFromSocketAndReconnect() {
        continueAfterFailure = false
        _ = probe("reset")
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_LINEAR_CARD_DEMO"] = "1"
        app.launchEnvironment["TASKFLOW_DEBUG_TOKEN"] = "fixture"
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "tasksheet:energy"
        app.launch()
        let grabber = app.buttons["Sheet Grabber"]
        XCTAssertTrue(grabber.waitForExistence(timeout: 15), app.debugDescription)
        grabber.swipeUp()
        let section = app.buttons["task-card.energy.section.subtasks"]
        if !app.buttons["Шаг до события"].exists {
            XCTAssertTrue(section.waitForExistence(timeout: 10), app.debugDescription)
            section.tap()
        }
        XCTAssertTrue(app.buttons["Шаг до события"].waitForExistence(timeout: 10), app.debugDescription)
        Thread.sleep(forTimeInterval: 2)
        let before = probe("counts")
        Thread.sleep(forTimeInterval: 12)
        XCTAssertEqual(probe("counts"), before, "Idle card must not issue periodic REST calls")
        _ = probe("change")
        XCTAssertTrue(app.buttons["Шаг после события"].waitForExistence(timeout: 10), app.debugDescription)
        _ = probe("change?silent=1")
        _ = probe("disconnect")
        XCTAssertTrue(app.buttons["Шаг после переподключения"].waitForExistence(timeout: 12), app.debugDescription)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "websocket-card-after-reconnect"
        shot.lifetime = .keepAlways
        add(shot)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(probe("counts")["__sockets"], 0, "Ordinary screen socket must close in background")
        _ = probe("reset")
        let background = probe("counts")
        Thread.sleep(forTimeInterval: 5)
        XCTAssertEqual(probe("counts"), background, "Background screen must not make requests")
        app.activate()
        XCTAssertTrue(app.buttons["Шаг до события"].waitForExistence(timeout: 12), app.debugDescription)
        app.terminate()
    }
}
