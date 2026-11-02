import XCTest

/// Разведка окон чата: карточка вопроса роли и ответы в ленте на ширине телефона.
final class QAChatWindowUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func tapTab(_ app: XCUIApplication, _ label: String) -> Bool {
        if app.buttons[label].exists { app.buttons[label].tap(); return true }
        if app.staticTexts[label].exists { app.staticTexts[label].tap(); return true }
        return false
    }

    func testChatWindows() {
        let app = XCUIApplication()
        app.launch()
        sleep(8)
        shot(app, "01-launch")
        print("TREE_START")
        print(app.debugDescription)
        print("TREE_END")

        if tapTab(app, "Входящие") {
            sleep(5)
            shot(app, "02-attention")
            app.swipeUp()
            sleep(2)
            shot(app, "03-attention-scrolled")
        }
        if tapTab(app, "Чат") {
            sleep(5)
            shot(app, "04-chats-list")
            print("TREE_CHATS_START")
            print(app.debugDescription)
            print("TREE_CHATS_END")
        }
    }
}
