import Foundation
import XCTest
#if canImport(TaskFlow)
@testable import TaskFlow
#endif

final class ChatWorkspaceTests: XCTestCase {
    private let json = """
    {"selected":"New-Todoist","branch":"roles/chat-c1",
     "options":[{"name":"CRM","git":true,"copy":false},{"name":"New-Todoist","git":true,"copy":true}]}
    """

    @objc func testDecodesAndTitles() throws {
        let state = try JSONDecoder().decode(ChatWorkspaceState.self, from: Data(json.utf8))
        XCTAssertEqual(state.selected, "New-Todoist")
        XCTAssertEqual(state.title, "New-Todoist")
        XCTAssertEqual(state.options.map(\.subtitle), [nil, "копия, ветка своя"])
    }

    @objc func testDefaultWhenNothingSelected() throws {
        let state = try JSONDecoder().decode(ChatWorkspaceState.self,
                                             from: Data(#"{"selected":null,"branch":null,"options":[]}"#.utf8))
        XCTAssertEqual(state.title, "Папка")
        XCTAssertNil(state.selected)
    }
}
