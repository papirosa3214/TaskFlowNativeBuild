import Foundation
import XCTest
@testable import TaskFlow
final class ChatSessionPreferencesTests: XCTestCase {
 func testProviderLevelsAreNotInvented() throws {
  let model=try JSONDecoder().decode(RoleModelOption.self,from:Data(#"{"id":"p/m","title":"M","thinkingLevels":["medium","high"]}"#.utf8))
  XCTAssertEqual(model.availableThinkingLevels,["medium","high"])
  XCTAssertFalse(model.availableThinkingLevels.contains("off"))
 }
 func testLegacyCatalogueDoesNotPretendToSupportTurningOff() throws {
  let model=try JSONDecoder().decode(RoleModelOption.self,from:Data(#"{"id":"old","title":"Old"}"#.utf8))
  XCTAssertEqual(model.availableThinkingLevels,[])
 }
 func testServerDefaultIsDistinctFromExplicitOff() throws {
  let value=try JSONDecoder().decode(ChatSessionPreferences.self,from:Data(#"{"model":null,"thinkingLevel":"off","configured":true}"#.utf8))
  XCTAssertEqual(value.thinkingLevel,"off")
  XCTAssertNil(value.model)
 }
 func testInvalidOldEffortIsClearedWhenModelChanges() {
  XCTAssertNil(ChatSessionPreferences.validThinking("off",available:["medium","high"]))
  XCTAssertEqual(ChatSessionPreferences.validThinking("low",available:["off","low"]),"low")
  XCTAssertNil(ChatSessionPreferences.validThinking(nil,available:["off"]))
 }
}
