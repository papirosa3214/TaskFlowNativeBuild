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

    /// Вложенная папка: на чипе — последнее имя, путь целиком — в шторке.
    @objc func testNestedTitleAndListing() throws {
        let state = try JSONDecoder().decode(ChatWorkspaceState.self,
            from: Data(#"{"selected":"New-Todoist/server","branch":"roles/chat-c1","options":[]}"#.utf8))
        XCTAssertEqual(state.title, "server")
        let listing = try JSONDecoder().decode(ChatFolderListing.self,
            from: Data(#"{"path":"CRM","parent":"","entries":[{"name":"app","path":"CRM/app","git":false}]}"#.utf8))
        XCTAssertEqual(listing.title, "CRM")
        XCTAssertEqual(listing.parent, "")
        XCTAssertEqual(listing.entries.first?.path, "CRM/app")
        let root = try JSONDecoder().decode(ChatFolderListing.self,
            from: Data(#"{"path":"","parent":null,"entries":[]}"#.utf8))
        XCTAssertEqual(root.title, "Проекты")
        XCTAssertNil(root.parent)
    }
}
