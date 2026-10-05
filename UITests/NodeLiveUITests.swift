import XCTest
final class NodeLiveUITests:XCTestCase {
 func testNodeLive(){
  let app=XCUIApplication();app.launchEnvironment["TASKFLOW_LINEAR_CARD_DEMO"]="1";app.launchEnvironment["TASKFLOW_DEBUG_TOKEN"]="fixture";app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"]="tasksheet:branch";app.launch()
  XCTAssertTrue(app.buttons["Sheet Grabber"].waitForExistence(timeout:15));app.buttons["Sheet Grabber"].swipeUp()
  if !app.buttons["plan-node-builder"].exists { app.buttons["task-card.branch.section.collaborationPlan"].tap() }
  let n=app.buttons["plan-node-builder"];XCTAssertTrue(n.waitForExistence(timeout:10));n.tap()
  XCTAssertFalse(app.staticTexts["Что сдать"].exists)
  XCTAssertFalse(app.staticTexts["Что сделать"].exists)
  let shot=XCTAttachment(screenshot:app.screenshot());shot.name="node-details";shot.lifetime = .keepAlways;add(shot)
  let live=app.buttons["plan-state-live"];XCTAssertTrue(live.waitForExistence(timeout:5));if !app.staticTexts["plan-slot-live-text"].waitForExistence(timeout:2) { live.tap() }
  XCTAssertTrue(app.staticTexts["plan-slot-live-text"].waitForExistence(timeout:5))
  XCTAssertTrue(app.staticTexts["Проверяю источники"].waitForExistence(timeout:10))
  app.swipeUp()
  XCTAssertTrue(app.staticTexts["Ожидаемый результат"].waitForExistence(timeout:5))
  let copy = app.buttons["plan-result-copy"]
  XCTAssertTrue(copy.waitForExistence(timeout:5))
  copy.tap()
  XCTAssertTrue(app.buttons["plan-result-copy"].label.contains("Скопировано"))
  let work=XCTAttachment(screenshot:app.screenshot());work.name="node-live";work.lifetime = .keepAlways;add(work)
  app.terminate();app.launch()
  XCTAssertTrue(app.buttons["Sheet Grabber"].waitForExistence(timeout:15));app.buttons["Sheet Grabber"].swipeUp()
  XCTAssertTrue(app.buttons["plan-node-builder"].waitForExistence(timeout:5), "План должен остаться раскрытым после повторного открытия")
  app.buttons["plan-node-builder"].tap()
  XCTAssertTrue(app.staticTexts["plan-slot-live-text"].waitForExistence(timeout:5), "Подробности работы слота должны оставаться раскрытыми")

  let restored=XCTAttachment(screenshot:app.screenshot());restored.name="restored-slot";restored.lifetime = .keepAlways;add(restored)
  app.buttons["plan-state-live"].tap()
  app.buttons["Готово"].tap()
  app.buttons["task-card.branch.section.collaborationPlan"].tap()
  app.terminate();app.launch()
  XCTAssertTrue(app.buttons["Sheet Grabber"].waitForExistence(timeout:15));app.buttons["Sheet Grabber"].swipeUp()
  XCTAssertFalse(app.buttons["plan-node-builder"].exists, "Свёрнутый план также должен остаться свёрнутым")
  app.buttons["task-card.branch.section.collaborationPlan"].tap();app.buttons["plan-node-builder"].tap()
  XCTAssertFalse(app.staticTexts["plan-slot-live-text"].exists, "Свёрнутые действия слота должны остаться свёрнутыми")

 }
 func testParentPlanLink() {
  let app=XCUIApplication();app.launchEnvironment["TASKFLOW_LINEAR_CARD_DEMO"]="1";app.launchEnvironment["TASKFLOW_DEBUG_TOKEN"]="fixture";app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"]="tasksheet:leaf";app.launch()
  XCTAssertTrue(app.buttons["Sheet Grabber"].waitForExistence(timeout:15));app.buttons["Sheet Grabber"].swipeUp()
  let link=app.buttons["branch-plan.parentLink"]
  XCTAssertTrue(link.waitForExistence(timeout:10))
  XCTAssertTrue(app.buttons["task-card.leaf.section.collaborationPlan"].exists)
  XCTAssertTrue(app.staticTexts["Общий план и запуск в родительской задаче"].exists)
  let shot=XCTAttachment(screenshot:app.screenshot());shot.name="parent-plan-link";shot.lifetime = .keepAlways;add(shot)
  link.tap()
  XCTAssertTrue(app.buttons["task-card.branch.section.collaborationPlan"].waitForExistence(timeout:10))
 }

}
