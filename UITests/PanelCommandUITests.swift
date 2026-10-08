import XCTest
final class PanelCommandUITests: XCTestCase {
    private let html = #"""
    <title>Проверка сервера</title>
    <style>body{font:18px -apple-system;color:white;background:#202020;padding:16px}button{font:18px -apple-system;padding:16px;min-height:48px}</style>
    <h2>Проверка сервера .110</h2>
    <button onclick="run(this)">Проверить сервер</button><pre id="result">Готово к запуску</pre>
    <script>
    async function run(button){button.disabled=true;try{const r=await TaskFlow.runCommand("printf 'Panel Live OK'");document.getElementById('result').textContent=r.stdout+'; код '+r.exitCode}catch(e){document.getElementById('result').textContent=e.message}finally{button.disabled=false}}
    </script>
    """#
    func testCancelConfirmAndResultInsideHTML() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_PANEL_PREVIEW"] = html
        app.launch()
        let button = app.webViews.buttons["Проверить сервер"]
        XCTAssertTrue(button.waitForExistence(timeout:20), app.debugDescription)
        button.tap()
        XCTAssertTrue(app.buttons["panel-command-confirm"].waitForExistence(timeout:10), app.debugDescription)
        app.buttons["Отмена"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Запуск отменён"].waitForExistence(timeout:10))
        button.tap()
        XCTAssertTrue(app.buttons["panel-command-confirm"].waitForExistence(timeout:5))
        app.buttons["panel-command-confirm"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Panel Live OK; код 0"].waitForExistence(timeout:40), app.debugDescription)
        let shot = XCTAttachment(screenshot: app.screenshot());shot.name="panel-live-server-result";shot.lifetime = .keepAlways;add(shot)
    }
    func testPanelWithoutOwnerPermissionCannotRequestExecution() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_PANEL_PREVIEW"] = html
        app.launchEnvironment["TASKFLOW_PANEL_DENIED"] = "1"
        app.launch()
        let button=app.webViews.buttons["Проверить сервер"]
        XCTAssertTrue(button.waitForExistence(timeout:20));button.tap()
        XCTAssertTrue(app.webViews.staticTexts["Действия доступны только владельцу в ответе роли"].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["panel-command-confirm"].exists)
    }
}
