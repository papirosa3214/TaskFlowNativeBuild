import XCTest
final class IntegrationPickerTriageUITests: XCTestCase {
 func testPicker() {
  continueAfterFailure = false
  let app = XCUIApplication()
  app.launchEnvironment["TASKFLOW_LINEAR_CARD_DEMO"] = "1"
  app.launchEnvironment["TASKFLOW_DEBUG_TOKEN"] = "fixture"
  app.launchEnvironment["TASKFLOW_DEBUG_ROUTE"] = "tasksheet:energy"
  app.launch()
  let grabber = app.buttons["Sheet Grabber"]
  if grabber.waitForExistence(timeout: 15) { grabber.swipeUp() }
  let details = app.buttons["task-card.energy.section.details"]
  if details.waitForExistence(timeout: 10) { details.tap() }
  print("PICKER_TREE_BEFORE: \(app.debugDescription)")
  let a = XCTAttachment(screenshot: app.screenshot()); a.name="before";a.lifetime = .keepAlways;add(a)
  let picker = app.buttons["integration-owner-picker"]
  XCTAssertTrue(picker.waitForExistence(timeout: 8), app.debugDescription)
  for (option, expected) in [("Не требуется", "Не требуется"), ("Не выбран", "Не выбран"), ("Автоматически", "Архитектор"), ("Разработчик", "Разработчик")] {
   picker.tap()
   let optionButton = app.buttons[option]
   XCTAssertTrue(optionButton.waitForExistence(timeout: 5), app.debugDescription)
   optionButton.tap()
   let changed = NSPredicate(format: "value == %@", expected)
   expectation(for: changed, evaluatedWith: picker)
   waitForExpectations(timeout: 8)
   let shot=XCTAttachment(screenshot: app.screenshot());shot.name=option;shot.lifetime = .keepAlways;add(shot)
  }
 }
}
