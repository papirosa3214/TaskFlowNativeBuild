import XCTest

/// Временный приёмочный тест: пустое состояние «Сегодня» в списке.
///
/// Задача (владелец 19.10.2026):
///   1. на вкладке «Сегодня» картинка задваивалась — статичная подложка под
///      `ScrollView` плюс подвижная внутри ленты; статичная убрана, осталась
///      подвижная, которая тянется за прокруткой;
///   2. в режиме «Часы» картинок не должно быть вовсе;
///   3. белый в трёх иллюстрациях приглушён.
///
/// Тест НЕ ищет иллюстрацию в дереве доступности: `TodayEmptyIllustration`
/// помечен `accessibilityHidden(true)`, поэтому там её нет by design, и
/// любая проверка по `app.images` была бы проверкой пустоты. Тест доводит
/// приложение до нужного состояния и прикладывает кадры; вывод делается по
/// ним глазами (`vision_analyze`), а не координатами по пикселям.
final class EmptyPlannerIllustrationUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    private func запустить() -> XCUIApplication {
        let app = XCUIApplication()
        // Вид «Список» принудительно: в «Часах» картинок нет по требованию.
        app.launchArguments = ["-taskflow_today_layout", "list"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Обзор"].waitForExistence(timeout: 25),
                      "Приложение не дошло до стартового экрана")
        return app
    }

    private func снять(_ app: XCUIApplication, _ имя: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = имя
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func открытьПланирование(_ app: XCUIApplication) {
        let кнопка = app.buttons["Сегодня"]
        XCTAssertTrue(кнопка.waitForExistence(timeout: 10), "Нет вкладки «Сегодня»")
        кнопка.tap()
        XCTAssertTrue(app.buttons["Фильтры"].waitForExistence(timeout: 15),
                      "Экран «Сегодня» не загрузился: нет кнопки «Фильтры»")
    }

    private func открытьВид(_ app: XCUIApplication, _ пункт: String) -> Bool {
        let меню = app.buttons["Вид"]
        if !меню.waitForExistence(timeout: 5) {
            app.buttons.matching(identifier: "ellipsis").firstMatch.tap()
        } else {
            меню.tap()
        }
        let выбор = app.buttons[пункт]
        guard выбор.waitForExistence(timeout: 5) else {
            if app.buttons["Отмена"].exists { app.buttons["Отмена"].tap() }
            return false
        }
        выбор.tap()
        _ = app.buttons["Фильтры"].waitForExistence(timeout: 15)
        return true
    }

    // MARK: - Кадры для визуальной приёмки

    /// Пустая вкладка «Сегодня» в списке: одна иллюстрация, она едет за
    /// прокруткой. Кадры до и после сдвига показывают разницу координат.
    func testПустоеСостояниеЕдетЗаПрокруткой() throws {
        let app = запустить()
        открытьПланирование(app)

        снять(app, "01-today-empty-top")
        app.swipeUp()
        app.swipeUp()
        снять(app, "02-today-empty-after-scroll")

        // Экран обязан остаться живым после прокрутки на пустой ленте.
        XCTAssertTrue(app.buttons["Фильтры"].exists,
                      "После прокрутки пустого состояния шапка пропала — экран сломался")
    }

    /// В режиме «Часы» картинок нет — на кадре должен быть только список.
    func testВРежимеЧасыИллюстрацийНет() throws {
        let app = запустить()
        открытьПланирование(app)

        guard открытьВид(app, "Часы") else {
            XCTFail("В меню вида нет пункта «Часы» — снять кадр режима не удалось")
            return
        }
        снять(app, "03-hours-empty")

        XCTAssertTrue(app.buttons["Фильтры"].exists,
                      "После переключения на «Часы» шапка пропала — экран сломался")
    }

    /// Три вкладки списка — по кадру на каждую, чтобы сверить картинки.
    func testВкладкиСпискаСоСвоимиКартинками() throws {
        let app = запустить()
        открытьПланирование(app)

        for вкладка in ["Входящие", "Внимание", "Сегодня"] {
            let кнопка = app.buttons[вкладка]
            if кнопка.waitForExistence(timeout: 5) {
                кнопка.tap()
                _ = app.buttons["Фильтры"].waitForExistence(timeout: 10)
            } else {
                // Вкладки могут называться иначе — кадр всё равно снимаем.
                XCTFail("Нет кнопки вкладки списка «\(вкладка)»")
            }
            снять(app, "04-tab-\(вкладка)")
        }
    }
}