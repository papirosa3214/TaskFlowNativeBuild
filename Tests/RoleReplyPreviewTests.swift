import XCTest
@testable import TaskFlow

final class RoleReplyPreviewTests: XCTestCase {
    func testEmptyServerPreviewIsEmpty() {
        XCTAssertTrue(RoleReplyMarkdown.previewSegments(of: [], key: "empty").isEmpty)
    }

    func testNonTextServerPreviewIsEmpty() {
        XCTAssertTrue(RoleReplyMarkdown.previewSegments(of: [.html("<p>x</p>")], key: "html").isEmpty)
    }
}
