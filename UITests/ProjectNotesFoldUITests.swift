import XCTest

/// Раздел «Документация» в карточке проекта сворачивается по тапу, а не уводит
/// на экран папки (владелец 05.10.2026: «просто эту папку свернуть, чтобы все
/// эти документики свернулись в эту папку»; «никуда я не провалюсь»).
///
/// Проверяется на живом сервере: проект «TaskFlow - NewTodoist» с привязанной
/// папкой документации. Токен владельца передаётся извне переменной
/// `TASKFLOW_TEST_TOKEN` (xcodebuild → `TEST_RUNNER_TASKFLOW_TEST_TOKEN=…`),
/// в репозитории его нет.
final class ProjectNotesFoldUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        if let token = ProcessInfo.processInfo.environment["TASKFLOW_TEST_TOKEN"], !token.isEmpty {
            app.launchEnvironment["TASKFLOW_DEBUG_TOKEN"] = token
        }
        app.launch()
        return app
    }

    func testProjectDocumentationFolderFolds() throws {
        let app = launch()

        // Проекты: вкладка называется «Проекты» (в текущей навигации может
        // жить внутри «Обзора» — тогда открываем через него).
        let projectsTab = app.buttons["Проекты"]
        if projectsTab.waitForExistence(timeout: 20) {
            projectsTab.tap()
        } else {
            let overview = app.buttons["Обзор"]
            XCTAssertTrue(overview.waitForExistence(timeout: 20), "нет ни «Проекты», ни «Обзор»")
            overview.tap()
        }

        let project = app.staticTexts["TaskFlow - NewTodoist"].firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 30), "проект с документацией не найден")
        project.tap()

        let folder = app.buttons["projectDocsFolder"]
        XCTAssertTrue(folder.waitForExistence(timeout: 30), "строка папки документации не найдена")

        // Развёрнуто по умолчанию: документы видны, фильтр на месте.
        XCTAssertEqual(folder.value as? String, "развёрнуто")
        let filter = app.buttons["День"]
        XCTAssertTrue(filter.waitForExistence(timeout: 15), "фильтр документов не виден в развёрнутом виде")
        let expanded = XCTAttachment(screenshot: app.screenshot())
        expanded.name = "expanded-filter-above-folder"
        expanded.lifetime = .keepAlways
        add(expanded)

        // Тап по папке — документы свернулись; навигации не произошло.
        folder.tap()
        XCTAssertEqual(folder.value as? String, "свёрнуто")
        XCTAssertTrue(app.navigationBars["TaskFlow - NewTodoist"].exists || app.staticTexts["Документация"].exists,
                      "уход со страницы проекта — папка должна только сворачиваться")
        XCTAssertFalse(filter.exists, "фильтр остался видимым в свёрнутом виде")
        let collapsed = XCTAttachment(screenshot: app.screenshot())
        collapsed.name = "collapsed-folder"
        collapsed.lifetime = .keepAlways
        add(collapsed)

        // Второй тап — документы вернулись.
        folder.tap()
        XCTAssertEqual(folder.value as? String, "развёрнуто")
        XCTAssertTrue(filter.waitForExistence(timeout: 15), "документы не вернулись после второго тапа")
    }
}
