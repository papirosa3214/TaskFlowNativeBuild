import XCTest
import WebKit
@testable import TaskFlow

final class PanelCommandTests: XCTestCase {
    func testCommandValidationPreservesExactTextAndRejectsInvalidBodies() {
        let command = "printf 'two words'; printf '\\n'"
        XCTAssertEqual(PanelCommandRequest.validated(["id":"a", "command":command])?.command, command)
        XCTAssertNil(PanelCommandRequest.validated(["id":"", "command":command]))
        XCTAssertNil(PanelCommandRequest.validated(["id":"a", "command":" \n"]))
        XCTAssertNil(PanelCommandRequest.validated(["id":"a", "command":String(repeating:"x", count:16001)]))
        XCTAssertNil(PanelCommandRequest.validated(["id":"a", "command":42]))
    }
    @MainActor func testDeniedBusyAndCancelDoNotExecute() {
        let bridge = PanelCommandBridge()
        let webView = WKWebView()
        let body = ["id":"a", "command":"printf 'test'"]
        bridge.receive(body, from:webView, allowed:false)
        XCTAssertNil(bridge.pending)
        XCTAssertFalse(bridge.running)
        bridge.receive(body, from:webView, allowed:true)
        XCTAssertEqual(bridge.pending?.id, "a")
        bridge.receive(["id":"b","command":"printf 'other'"], from:webView, allowed:true)
        XCTAssertEqual(bridge.pending?.id, "a")
        bridge.cancel()
        XCTAssertNil(bridge.pending)
        XCTAssertFalse(bridge.running)
    }
}
