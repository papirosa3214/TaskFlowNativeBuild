import XCTest
final class PlanWorkSelectionUITests: XCTestCase {
 func testChoicesPersistWithoutCompletionControls() {
  let app=XCUIApplication();app.launchEnvironment["TASKFLOW_LINEAR_CARD_DEMO"]="1";app.launchEnvironment["TASKFLOW_DEBUG_TOKEN"]="fixture";app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"]="tasksheet:choice";app.launch()
  XCTAssertTrue(app.buttons["Sheet Grabber"].waitForExistence(timeout:15));app.buttons["Sheet Grabber"].swipeUp()
  let section=app.buttons["task-card.choice.section.subtasks"]
  XCTAssertTrue(section.waitForExistence(timeout:10));if !app.buttons["plan-choice.work.original"].exists { section.tap() }
  let original=app.buttons["plan-choice.work.original"],planned=app.buttons["plan-choice.work.planned"]
  XCTAssertTrue(original.waitForExistence(timeout:10));XCTAssertTrue(planned.exists)
  let before=XCTAttachment(screenshot:app.screenshot());before.name="before-choice";before.lifetime = .keepAlways;add(before)
  planned.tap()
  XCTAssertTrue(app.buttons["plan-choice-reset.work"].waitForExistence(timeout:10));XCTAssertFalse(original.exists)
  app.terminate();app.launch();XCTAssertTrue(app.buttons["Sheet Grabber"].waitForExistence(timeout:15));app.buttons["Sheet Grabber"].swipeUp()
  XCTAssertTrue(app.buttons["plan-choice-reset.work"].waitForExistence(timeout:10));XCTAssertFalse(app.buttons["plan-choice.work.original"].exists)
  let after=XCTAttachment(screenshot:app.screenshot());after.name="saved-choice";after.lifetime = .keepAlways;add(after)
  app.buttons["plan-choice-reset.work"].tap();XCTAssertTrue(app.buttons["plan-choice.work.original"].waitForExistence(timeout:10))
 }
}
