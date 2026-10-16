import XCTest

/// Временный тест: раздел «Сервер» → пункт «Удалённые машины» → экран.
///
/// LOCK-REMOTE-MACHINES-ROW, 16.10.2026. Владелец (телефон): «Какие, блядь,
/// машин? Чего за повторить, кого я тут повторю в разделе "Сервер"? Почему
/// здесь нет раздела "Удаленный хост", куда я нажимаю».
///
/// Проверяем ровно это: в «Сервере» есть ПУНКТ с шевроном (а не блок с
/// машинами в потоке), и по тапу открывается отдельный экран, где и живут
/// сообщение об ошибке и «Повторить».
///
/// Элементы ищем по `accessibilityIdentifier` — тап по координатам кадра
/// промахивается (points против пикселей ×3), см. AGENT-CYCLE.md §7.
final class RemoteMachinesRowUITests: XCTestCase {

    private func openServerSection() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "settings"
        app.launch()

        let пункт = app.buttons["settings-remote-machines"]
        for _ in 0..<14 {
            if пункт.exists && пункт.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(пункт.waitForExistence(timeout: 20),
                      "в разделе «Сервер» нет пункта «Удалённые машины»:\n\(app.debugDescription)")
        return app
    }

    /// Главное: в «Сервере» — строка с шевроном, а не ошибка в потоке.
    func testServerSectionShowsRowNotError() {
        continueAfterFailure = false
        let app = openServerSection()

        let пункт = app.buttons["settings-remote-machines"]
        XCTAssertTrue(пункт.exists, "пункт «Удалённые машины» не найден")

        // Шеврон — признак перехода на отдельный экран.
        XCTAssertTrue(
            пункт.descendants(matching: .any).matching(identifier: "chevron.right").firstMatch.exists,
            "в пункте нет шеврона — это не переход на экран"
        )

        // Ошибки загрузки в потоке «Сервера» быть не должно: она относится
        // к экрану машин, а не к списку настроек.
        let чужаяОшибка = app.buttons["remote-machines-retry"]
        XCTAssertFalse(
            чужаяОшибка.exists,
            "кнопка «Повторить» оказалась прямо в разделе «Сервер»"
        )

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "01-server-section-remote-machines-row"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// По тапу открывается отдельный экран со своей шапкой.
    func testRowOpensDedicatedScreen() {
        continueAfterFailure = false
        let app = openServerSection()

        app.buttons["settings-remote-machines"].tap()

        let экран = app.descendants(matching: .any)
            .matching(identifier: "remote-machines-screen").firstMatch
        XCTAssertTrue(экран.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["УДАЛЁННЫЕ МАШИНЫ"].exists,
                      "на экране нет своей шапки «Удалённые машины»")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "02-remote-machines-screen"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Состояние ошибки принадлежит экрану: баннер и «Повторить» здесь,
    /// а не в списке настроек.
    func testErrorStateLivesOnDedicatedScreen() {
        continueAfterFailure = false
        let app = openServerSection()
        app.buttons["settings-remote-machines"].tap()

        // Если машины загрузились — ошибки нет, и кадр состояния ошибки
        // снимается на фикстуре. Состояние загрузки/списка снимаем всегда.
        let ошибка = app.buttons["remote-machines-retry"]
        if ошибка.waitForExistence(timeout: 6) {
            XCTAssertTrue(
                app.descendants(matching: .any)
                    .matching(identifier: "remote-machines-error").firstMatch.exists,
                "на экране нет баннера ошибки"
            )
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "03-remote-machines-error-state"
            shot.lifetime = .keepAlways
            add(shot)
        } else {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "03-remote-machines-loaded-state"
            shot.lifetime = .keepAlways
            add(shot)
            XCTContext.runActivity(named: "Машины загрузились — состояние ошибки снимается на фикстуре") { _ in }
        }
    }
}
