import XCTest
import UIKit

/// Кадр настоящего чата после перехода из корневой вкладки.
final class ChatVoiceComposerUITests: XCTestCase {
    func testIdleComposerMatchesVoiceMessageLab() {
        let app = XCUIApplication()
        app.launch()
        let tab = app.buttons["Чат"]
        XCTAssertTrue(tab.waitForExistence(timeout: 25))
        tab.tap()
        let capsule = app.images["Удерживайте для начала записи"]
        XCTAssertTrue(capsule.waitForExistence(timeout: 15))
        let addButton = app.buttons["Добавить вложение"]
        XCTAssertTrue(addButton.exists)
        let screenshot = app.screenshot().image
        guard let source = screenshot.cgImage else { return XCTFail("Нет кадра симулятора") }
        let scale = CGFloat(source.width) / app.frame.width
        let frame = addButton.frame.union(capsule.frame).insetBy(dx: -8, dy: -8)
        let pixels = CGRect(x: frame.minX * scale, y: frame.minY * scale,
                            width: frame.width * scale, height: frame.height * scale)
        guard let crop = source.cropping(to: pixels) else { return XCTFail("Не удалось выделить композер") }
        let attachment = XCTAttachment(image: UIImage(cgImage: crop))
        attachment.name = "chat-voice-composer-idle"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
