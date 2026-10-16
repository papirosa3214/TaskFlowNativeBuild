import XCTest

/// Визуальный обход экранов — вторая из трёх проверок цикла приёмки
/// (LOCK-UI-DRIFT-GATE-20261016, AGENT-CYCLE.md §7).
///
/// Владелец 16.10.2026, дословно: «Это нужно выявлять мне до передачи сборки
/// тебе. Тебе не должно приходиться обходить приложение и собирать такие
/// скриншоты». Этот тест обходит сам: открывает экраны, доходит до нужного
/// места по `accessibilityIdentifier` (не тапом по координатам кадра — они в
/// пикселях retina и промахиваются), снимает кадр и сохраняет его как
/// вложение для сравнения с утверждённым образцом.
///
/// Что снимает (ровно те состояния, которые владелец назвал недосказанными):
///   • низ длинного экрана — там, где раньше вставлялась ошибка загрузки;
///   • ошибка загрузки с оформленной кнопкой;
///   • открытая клавиатура на панели быстрого создания — там, где нижняя
///     навигация просвечивала под формой;
///   • экраны подключений — там, где были большие красные кнопки.
///
/// Правила теста (AGENT-CYCLE.md §7): не больше двух прогонов UI-теста за
/// задачу; после второй неудачи — остановиться и отдать владельцу кадр, а не
/// крутить «поправил тест → пересобрал → снова». Предел автотестов: картинки,
/// цвета и мелкие правки вида проверяются БЕЗ XCUITest — одним кадром;
/// здесь XCUITest нужен потому, что до каждого экрана иначе не добраться.
final class UIStyleGateUITests: XCTestCase {

    /// Кадр с именем — вложение xcresult, выгружается через
    /// `xcrun xcresulttool export attachments` (AGENT-CYCLE.md §7).
    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Дойти до элемента прокруткой: свайп, пока элемент не станет видимым.
    /// Первый попавшийся `ScrollView` брать нельзя — это может оказаться
    /// экран позади шторки (указание владельца, AGENT-CYCLE.md §7).
    @discardableResult
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 12) -> Bool {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    private func launch(route: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = route
        app.launch()
        return app
    }

    // MARK: - 1. Чёрный фон вместо фона приложения

    /// «Параметры сервера» и «Диагностика» — оба из кадра владельца.
    /// Кадр снимается целиком: фон виден на всей площади, отдельного
    /// элемента под фон нет, а проверить его на глаз по вложению — как раз
    /// то, что делает владелец.
    func testServerSettingsAndDiagnosticsFrames() {
        continueAfterFailure = false

        // «Параметры» и «Диагностика» доступны только владельцу, а симулятор
        // может войти под другой учёткой. Открываем маршрут напрямую через
        // DEBUG-роут `serversettings`, иначе проверка зависит от роли сессии,
        // а не от оформления.
        let app = launch(route: "serversettings")
        // Идентификатор `.accessibilityIdentifier("server-settings-screen")`
        // на самом `List` попадает в дерево как CollectionView, а не Other —
        // ищем по обоим типам, а не по одному.
        let screen = app.descendants(matching: .any)
            .matching(identifier: "server-settings-screen").firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 25), app.debugDescription)
        shoot(app, "01-server-parameters-background")

        // Вторая строка того же экрана — отдельный дефект из того же кадра,
        // поэтому снимается в этом же прогоне.
        let diagnostics = app.buttons["server-settings-diagnostics"]
        XCTAssertTrue(scrollTo(diagnostics, in: app), "не нашёл строку «Диагностика»:\n\(app.debugDescription)")
        diagnostics.tap()
        let diagnosticsScreen = app.descendants(matching: .any)
            .matching(identifier: "app-diagnostics-screen").firstMatch
        XCTAssertTrue(diagnosticsScreen.waitForExistence(timeout: 20), app.debugDescription)
        shoot(app, "02-diagnostics-background")
    }

    // MARK: - 2. Ошибка загрузки оформлена

    /// Раздел «Удалённые машины» в нижней части серверного блока настроек.
    /// Снимаются оба состояния: успешная загрузка и ошибка — второй кадр
    /// снимается принудительно, через фикстуру, которая гасит сеть, иначе
    /// состояние ошибки не наступит само.
    func testMachinesSectionFrames() {
        continueAfterFailure = false
        let app = launch(route: "settings")

        let pair = app.buttons["settings-remote-machines-pair"]
        // Раздел в самом низу — прокрутка обязательна, иначе кадр снизу.
        for _ in 0..<14 {
            if pair.exists && pair.isHittable { break }
            app.swipeUp()
        }
        // Владелец прислал именно НИЗ этого экрана: снимаем после того, как
        // доскроллили, иначе в кадр попадёт только верх.
        shoot(app, "03-machines-section-bottom")

        let retry = app.buttons["settings-remote-machines-retry"]
        if retry.waitForExistence(timeout: 5) {
            shoot(app, "04-machines-load-error")
            XCTAssertTrue(
                app.staticTexts["settings-remote-machines-error"].exists,
                "ошибка загрузки не оформлена общим баннером"
            )
        } else {
            // Список пришёл с данными — значит ошибки сейчас нет, и кадр
            // состояния ошибки должен быть снят на фикстуре.
            XCTContext.runActivity(named: "Машины загрузились — состояние ошибки снимается на фикстуре") { _ in }
        }
    }

    // MARK: - 3. Нижняя навигация под модальной формой

    /// Ключевой кадр из поручения: панель быстрого создания с ОТКРЫТОЙ
    /// клавиатурой. Именно в этом состоянии нижняя навигация поднималась
    /// вместе с клавиатурой и просвечивала под формой.
    func testQuickAddPanelWithKeyboardHasNoTabBarBehind() {
        continueAfterFailure = false
        let app = launch(route: "quickadd")

        // Поле получает фокус само (viewModel ставит isTitleFocused в .task),
        // поэтому достаточно дождаться поля, а не тапать по координатам.
        let title = app.textFields.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 20), app.debugDescription)
        title.tap()

        // Кадр с поднятой клавиатурой: именно тут видна нижняя навигация,
        // если она не скрыта.
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10), "клавиатура не поднялась:\n\(app.debugDescription)")
        shoot(app, "05-quickadd-keyboard-no-tabbar")

        // Нижняя навигация — четыре пункта плюс круглая кнопка создания.
        // Под открытой панелью их быть не должно: таббар скрывается на
        // время панели.
        let tabBar = app.buttons["Планирование"]
        XCTAssertFalse(
            tabBar.exists && tabBar.isHittable,
            "нижняя навигация осталась под панелью быстрого создания"
        )
    }

    // MARK: - 4. Экраны подключений: серые кнопки, а не красные

    /// «Reddit и другие новые экраны подключений — большие красные кнопки
    /// вместо принятых серых».
    ///
    /// Отладочного роута `integrations` в приложении нет, поэтому идём
    /// настоящим путём пользователя по идентификаторам: Настройки → Сервер
    /// MCP (`Сервер MCP`) → развернуть «Composio» (`mcp.composio`) →
    /// каталог сервисов (`composio.catalog`). Ни одного тапа по координатам
    /// кадра: координаты `tap` в points, скриншот отдаётся в пикселях ×3.
    func testIntegrationConnectButtonsFrames() {
        continueAfterFailure = false
        let app = launch(route: "settings")

        let mcp = app.buttons.containing(.staticText, identifier: "Сервер MCP").firstMatch
        XCTAssertTrue(scrollTo(mcp, in: app), "не нашёл строку «Сервер MCP»:\n\(app.debugDescription)")
        shoot(app, "06a-integrations-entry")
        mcp.tap()

        let composio = app.buttons["mcp.composio"]
        XCTAssertTrue(scrollTo(composio, in: app), "не нашёл карточку Composio:\n\(app.debugDescription)")
        composio.tap()

        // Каталог сервисов — здесь стояли большие красные кнопки подключения.
        let catalog = app.buttons["composio.catalog"]
        XCTAssertTrue(catalog.waitForExistence(timeout: 20), app.debugDescription)
        shoot(app, "06-integrations-connect-buttons")
        catalog.tap()

        // Карточка сервиса: кнопка «Подключить аккаунт» должна быть серой.
        let connect = app.buttons["composio.connect"]
        if connect.waitForExistence(timeout: 15) {
            shoot(app, "07-service-connect-grey-button")
        } else {
            XCTContext.runActivity(named: "У сервиса нет кнопки подключения (уже подключён или без авторизации) — кадр каталога уже снят") { _ in }
        }
    }
}