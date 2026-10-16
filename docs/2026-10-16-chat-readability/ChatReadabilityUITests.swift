import XCTest
final class ChatReadabilityUITests: XCTestCase {
 func testGroupReplyAppearance() {
  continueAfterFailure = false
  let app = XCUIApplication()
  app.launchArguments += ["-hints.enabled", "NO"]
  app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "chat"
  app.launch()
  XCTAssertTrue(app.buttons["chats.menu"].waitForExistence(timeout: 25))
  let secretary = app.staticTexts["Помощник владельца"].firstMatch
  XCTAssertTrue(secretary.waitForExistence(timeout: 15))
  secretary.tap()
  XCTAssertTrue(app.buttons["Чат: название и участники"].waitForExistence(timeout: 20))
  sleep(3)
  let shot = XCTAttachment(screenshot: app.screenshot())
  shot.name = "group-reply"
  shot.lifetime = .keepAlways
  add(shot)
 }
}
