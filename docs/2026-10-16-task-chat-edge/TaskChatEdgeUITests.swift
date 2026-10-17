import XCTest
final class TaskChatEdgeUITests: XCTestCase {
 func testOnlyTopHandleClosesTaskChat() {
  continueAfterFailure = false
  let app = XCUIApplication()
  app.launchArguments += ["-hints.enabled", "NO"]
  app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "task:c70e1888-767d-4cf5-81e2-29147d628132"
  app.launch()
  let content = app.collectionViews["task.content.c70e1888-767d-4cf5-81e2-29147d628132"]
  XCTAssertTrue(content.waitForExistence(timeout: 25))
  let section = app.buttons["Чат по задаче"].firstMatch
  for _ in 0..<18 {
   if section.exists && section.isHittable { break }
   content.swipeUp()
  }
  XCTAssertTrue(section.exists)
  section.tap()
  let chat = app.buttons["task.chat.858a3e90-7376-4cd4-bee3-7ba9a5190024"]
  if !chat.isHittable { content.swipeUp() }
  XCTAssertTrue(chat.waitForExistence(timeout: 5))
  chat.tap()
  let details = app.buttons["Чат: название и участники"]
  XCTAssertTrue(details.waitForExistence(timeout: 20))
  let area = app.scrollViews["chat.feed"]
  XCTAssertTrue(area.waitForExistence(timeout: 10))
  // Несколько жестов вниз: сначала до начала истории, затем overscroll.
  for _ in 0..<4 { if !details.exists { break }; area.swipeDown() }
  let shot = XCTAttachment(screenshot: app.screenshot())
  shot.name = "after-feed-swipes"; shot.lifetime = .keepAlways; add(shot)
  XCTAssertTrue(details.exists, "Свайпы по сообщениям не должны закрывать чат")
  let handle = app.buttons["task.chat.dismiss-handle"]
  XCTAssertTrue(handle.exists)
  let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
  start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 160)))
  let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: handle)
  XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
  XCTAssertTrue(chat.isHittable, "Верхняя ручка возвращает карточку")
 }
}
