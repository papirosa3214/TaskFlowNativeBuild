import XCTest

/// Временный тест под LOCK-SUBTASK-STREAM-REMOVE-20261010. После сверки удаляется.
///
/// Проверяет ровно то, что просил владелец: под списком шагов живой стрим
/// (текст «чем занят агент» и последние пять действий) больше не рисуется, а
/// ряд иконок с числом действий стоит ВЫШЕ первого шага.
///
/// Данные — изолированный fixture `Tools/subtask-stream-fixture.py`
/// (`TASKFLOW_TEST_API_URL`): на живой задаче активности может не быть, и
/// тогда проверять было бы нечего.
final class SubtaskStreamUITests: XCTestCase {

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testStreamGoneIconsAboveSubtasks() {
        let app = XCUIApplication()
        app.launchEnvironment["TASKFLOW_TEST_API_URL"] = "http://127.0.0.1:3319"
        app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "task:live"
        app.launch()

        let section = app.buttons["task-card.live.section.subtasks"]
        XCTAssertTrue(section.waitForExistence(timeout: 30), "секция «Подзадачи» не найдена")
        // Секция может остаться раскрытой с прошлого прогона (состояние в
        // UserDefaults) — тогда тап её свернёт. Раскрываем только когда шагов
        // под заголовком действительно нет.
        let firstStepTitle = "Собрать и проверить правку карточки"
        if !app.staticTexts[firstStepTitle].exists { section.tap() }
        XCTAssertTrue(app.staticTexts[firstStepTitle].waitForExistence(timeout: 10),
                      "список шагов не раскрыт")
        sleep(4)
        shot(app, "subtasks-expanded")

        // 1. Ряд иконок есть: счётчик действий на месте (иконки — картинки,
        //    за ними ищем по счётчику).
        let counter = app.staticTexts["10 действий"]
        XCTAssertTrue(counter.waitForExistence(timeout: 10), "нет числа действий в ряду иконок")

        // 2. Живого стрима под шагами нет: ни текста активности, ни списка
        //    последних действий («Действие N: …»), ни счётчика «Действий: N».
        let leftovers = app.descendants(matching: .any)
            .matching(NSPredicate(format:
                "label CONTAINS[c] 'Действие 0' OR label CONTAINS[c] 'Действий:' OR label CONTAINS[c] 'последние действия' OR label CONTAINS[c] 'Разбирает правку'"))
            .count
        XCTAssertEqual(leftovers, 0, "живой стрим под шагами остался: \(leftovers) элементов")

        // 3. Ряд иконок ВЫШЕ первого шага (регрессия на «поднять выше подзадач»).
        let firstStep = app.staticTexts[firstStepTitle]
        let chipsFrame = counter.frame
        let stepFrame = firstStep.frame
        print("MARK chipsY=\(Int(chipsFrame.minY))..\(Int(chipsFrame.maxY)) stepY=\(Int(stepFrame.minY)) leftovers=\(leftovers)")
        XCTAssertLessThanOrEqual(chipsFrame.maxY, stepFrame.minY,
                                 "ряд иконок должен быть выше первого шага")

        // 4. Свёрнутая секция тоже сохраняет признак работы агента: ряд иконок
        //    остаётся и под шевроном (иначе после снятия стрима там пусто).
        section.tap()
        sleep(2)
        let collapsedCounter = app.staticTexts["10 действий"]
        let collapsedChipsExist = collapsedCounter.exists
        print("MARK collapsedChips=\(collapsedChipsExist)")
        XCTAssertTrue(collapsedChipsExist, "в свёрнутой секции ряд иконок пропал")
    }
}