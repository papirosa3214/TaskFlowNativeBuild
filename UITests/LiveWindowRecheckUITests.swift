import XCTest
final class LiveWindowRecheckUITests: XCTestCase {
 func testWindow() {
  continueAfterFailure = false
  let app = XCUIApplication()
  app.launchEnvironment["TASKFLOW_LINEAR_CARD_DEMO"] = "1"
  app.launchEnvironment["TASKFLOW_DEBUG_TOKEN"] = "fixture"
  app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "tasksheet:energy"
  app.launch()
  let grabber = app.buttons["Sheet Grabber"]
  XCTAssertTrue(grabber.waitForExistence(timeout: 15), app.debugDescription)
  grabber.swipeUp()
  let section = app.buttons["task-card.energy.section.collaborationPlan"]
  XCTAssertTrue(section.waitForExistence(timeout: 10))
  let node = app.buttons["plan-node-builder"]
  if !node.exists { section.tap() }
  for _ in 0..<5 { if node.exists && node.isHittable { break }; app.swipeUp() }
  XCTAssertTrue(node.waitForExistence(timeout: 10), app.debugDescription)
  node.tap()
  let disclosure = app.descendants(matching: .any)["plan-state-live"].firstMatch
  XCTAssertTrue(disclosure.waitForExistence(timeout: 10), app.debugDescription)
  let window = app.scrollViews["plan-slot-live-window"]
  if !window.exists { disclosure.tap() }
  XCTAssertTrue(window.waitForExistence(timeout: 10), app.debugDescription)
  XCTAssertTrue(app.staticTexts["Событие 39: проверяется накопленная история роли в ограниченном окне"].waitForExistence(timeout: 10), app.debugDescription)
  let frame = window.frame
  XCTAssertEqual(frame.height / app.frame.height, 0.5, accuracy: 0.03)
  let before = XCTAttachment(screenshot: app.screenshot()); before.name = "expanded-bottom"; before.lifetime = .keepAlways; add(before)
  window.swipeDown()
  XCTAssertEqual(window.frame.height, frame.height, accuracy: 2)
  XCTAssertEqual(window.frame.minY, frame.minY, accuracy: 2)
  let scrolled = XCTAttachment(screenshot: app.screenshot()); scrolled.name = "internal-scroll"; scrolled.lifetime = .keepAlways; add(scrolled)
  disclosure.tap()
  XCTAssertFalse(window.exists)
  disclosure.tap()
  XCTAssertTrue(window.waitForExistence(timeout: 5))
  XCTAssertEqual(window.frame.height, frame.height, accuracy: 2)
  let reopened = XCTAttachment(screenshot: app.screenshot()); reopened.name = "reopened"; reopened.lifetime = .keepAlways; add(reopened)
  print("LIVE_WINDOW_FRAME: \(frame); screen: \(app.frame)")
  app.terminate()
 }
}
