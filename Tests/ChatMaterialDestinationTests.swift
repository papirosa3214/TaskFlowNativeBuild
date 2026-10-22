import Foundation
import XCTest
@testable import TaskFlow

final class ChatMaterialDestinationTests: XCTestCase {
    let id = "aae18cc4-1dcc-4ea9-80a9-ee4b0e5ea9ad"
    func testLibraryLinkOpensOriginalNote() {
        XCTAssertEqual(ChatMaterialDestination.resolve("note://" + id), .note(id))
    }
    func testExistingDocumentIDStillOpensNote() {
        XCTAssertEqual(ChatMaterialDestination.resolve(id, kind: "document"), .note(id))
        XCTAssertEqual(ChatMaterialDestination.resolve(id, kind: "artifact"), .note(id))
        XCTAssertNil(ChatMaterialDestination.resolve(id, kind: "file"))
    }
    func testTaskLinkStaysInternal() {
        XCTAssertEqual(ChatMaterialDestination.resolve("task://" + id), .task(id))
    }
    func testExternalLinkAndUnopenablePaths() {
        XCTAssertEqual(ChatMaterialDestination.resolve("https://example.com/report"), .web(URL(string: "https://example.com/report")!))
        for ref in ["/tmp/backup.db", "docs/report.md", "file:///tmp/report.md", "note://", "note://../secret", "javascript:alert(1)"] {
            XCTAssertNil(ChatMaterialDestination.resolve(ref))
        }
    }
}
