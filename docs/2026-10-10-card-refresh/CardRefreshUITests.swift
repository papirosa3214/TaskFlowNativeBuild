import XCTest
final class CardRefreshUITests: XCTestCase {
 func testRoleSurvivesRefresh() {
  continueAfterFailure = false
  let app = XCUIApplication()
  app.launchEnvironment["TASKFLOW_LINEAR_CARD_DEMO"] = "1"
  app.launchEnvironment["TASKFLOW_DEBUG_TOKEN"] = "fixture"
  app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "tasksheet:energy"
  app.launchEnvironment["TASKFLOW_TEST_API_URL"] = "http://127.0.0.1:3318"
  app.launch()
  let grabber = app.buttons["Sheet Grabber"]
  XCTAssertTrue(grabber.waitForExistence(timeout: 15))
  grabber.swipeUp()
  let section = app.buttons["task-card.energy.section.collaborationPlan"]
  XCTAssertTrue(section.waitForExistence(timeout: 10))
  let node = app.buttons["plan-node-builder"]
  if !node.exists { section.tap() }
  for _ in 0..<5 { if node.exists && node.isHittable { break }; app.swipeUp() }
  XCTAssertTrue(node.waitForExistence(timeout: 10), app.debugDescription)
  node.tap()
  let role = app.descendants(matching: .any)["plan-state-live"].firstMatch
  XCTAssertTrue(role.waitForExistence(timeout: 10), app.debugDescription)
  let before = XCTAttachment(screenshot: app.screenshot()); before.name = "role-before-refresh"; before.lifetime = .keepAlways; add(before)
  let sent = expectation(description: "refresh sent")
  URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:3318/probe/change")!) { _,_,_ in sent.fulfill() }.resume()
  wait(for: [sent], timeout: 5)
  let settled = expectation(description: "observe asynchronous refresh")
  DispatchQueue.main.asyncAfter(deadline: .now() + 4) { settled.fulfill() }
  wait(for: [settled], timeout: 6)
  let after = XCTAttachment(screenshot: app.screenshot()); after.name = "role-after-refresh"; after.lifetime = .keepAlways; add(after)
  XCTAssertTrue(role.exists, "Role detail dismissed by task refresh: " + app.debugDescription)
  app.buttons["Готово"].tap()
  let journal = app.buttons["task-card.energy.section.journal"]
  for _ in 0..<2 { app.swipeUp() }
  XCTAssertTrue(journal.exists && journal.isHittable, app.debugDescription)
  let journalY = journal.frame.minY
  let changed = expectation(description: "second refresh")
  URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:3318/probe/change")!) { _,_,_ in changed.fulfill() }.resume()
  wait(for: [changed], timeout: 5)
  XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "Шаг после переподключения")).firstMatch.waitForExistence(timeout: 10), app.debugDescription)
  XCTAssertEqual(journal.frame.minY, journalY, accuracy: 3, "Card scroll jumped on refresh")
  let scroll = XCTAttachment(screenshot: app.screenshot()); scroll.name = "scroll-after-refresh"; scroll.lifetime = .keepAlways; add(scroll)
  app.terminate()
 }
}
