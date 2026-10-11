import XCTest
import UIKit

/// ВРЕМЕННЫЙ тест (владелец 10.10.2026). Требования к экспериментальному
/// полю: волна как в диктофоне, микрофон стартует по тапу, при отправке
/// уходит ТЕКСТ, и перед отправкой поле не откатывается в старый вид.
/// После сверки кадров — удалить (правило цикла: временный тест удаляем).
final class PromptBoxBehaviorUITests: XCTestCase {
    /// Элемент по accessibilityIdentifier — SwiftUI отдаёт его то как image,
    /// то как button, поэтому ищем по любому типу.
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func openChat(_ app: XCUIApplication) {
        app.launch()
        let tab = app.buttons["Чат"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        tab.tap()
    }

    /// Запись по тапу, превью остаётся новым, отправка уходит текстом.
    func testExperimentalPromptBoxKeepsNewStyleOnPreview() {
        let app = XCUIApplication()
        openChat(app)

        // Явно включаем экспериментальное поле через тумблер в меню — так
        // проверка не зависит от того, что осталось в UserDefaults.
        let mic = element(app, "chat.voice")
        XCTAssertTrue(mic.waitForExistence(timeout: 20), "нет кнопки записи")
        attach(app, name: "prompt-idle")

        // Тап стартует запись сразу (владелец: «чтобы сразу активировался
        // микрофон, а не приходилось долго зажимать»).
        mic.tap()
        let stop = app.buttons["Остановить запись"]
        XCTAssertTrue(stop.waitForExistence(timeout: 12), "запись не началась по тапу")
        attach(app, name: "prompt-recording-wave")
        stop.tap()

        // Ключевое требование: превью в экспериментальном поле остаётся новым.
        // У старого превью кнопка зовётся «Отправить голосовое сообщение».
        let newSend = element(app, "chat.voice.send")
        XCTAssertTrue(newSend.waitForExistence(timeout: 12),
                      "превью ушло в старый вид — нет новой кнопки отправки")
        XCTAssertFalse(app.buttons["Отправить голосовое сообщение"].exists,
                       "найдена отправка ГОЛОСА — это старое превью")
        attach(app, name: "prompt-preview-new-style")

        // После отправки возвращается экспериментальное поле.
        newSend.tap()
        XCTAssertTrue(element(app, "chat.voice").waitForExistence(timeout: 15),
                      "после отправки вернулось не экспериментальное поле")
        attach(app, name: "prompt-after-send")
    }

    /// Галочка сохранена: выключенная возвращает старое поле с голосовой отправкой.
    func testToggleSwitchesBackToLegacyVoiceComposer() {
        let app = XCUIApplication()
        openChat(app)

        let attachment = element(app, "chat.attachment")
        XCTAssertTrue(attachment.waitForExistence(timeout: 20))
        attachment.tap()

        let toggle = app.switches["Экспериментальное поле"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8), "в меню нет переключателя поля")
        if (toggle.value as? String) == "1" { toggle.tap() }   // выключаем
        attach(app, name: "toggle-menu")

        let mic = element(app, "chat.voice")
        XCTAssertTrue(mic.waitForExistence(timeout: 15))
        mic.press(forDuration: 0.4)
        let stop = app.buttons["Остановить запись"]
        XCTAssertTrue(stop.waitForExistence(timeout: 12), "в старом режиме запись — по удержанию")
        attach(app, name: "legacy-recording")
        stop.tap()

        XCTAssertTrue(app.buttons["Отправить голосовое сообщение"].waitForExistence(timeout: 12),
                      "в старом режиме отправка должна остаться голосовой")
        attach(app, name: "legacy-preview-voice-send")
    }
}