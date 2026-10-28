import XCTest

final class ComposioConnectionsTests: XCTestCase {
    func testConnectedGitHubOutsideCatalogPageRemainsVisible() throws {
        let data = Data(#"{"catalog":[],"services":[{"slug":"github","name":"GitHub","connected":true}]}"#.utf8)
        let model = try JSONDecoder().decode(ComposioConnectionOverview.self, from: data)
        XCTAssertEqual(model.connectedServices.map(\.slug), ["github"])
    }
    func testResolvedStatusWinsAndUnknownOrDisconnectedAreHidden() throws {
        let data = Data(#"{"catalog":[{"slug":"github","name":"GitHub","connected":false,"noAuth":false},{"slug":"linear","name":"Linear","connected":true,"noAuth":false}],"services":[{"slug":"github","name":"GitHub","connected":true},{"slug":"linear","name":"Linear","connected":false},{"slug":"unknown","name":null,"connected":null}]}"#.utf8)
        let model = try JSONDecoder().decode(ComposioConnectionOverview.self, from: data)
        XCTAssertEqual(model.connectedServices.map(\.slug), ["github"])
    }
    func testDuplicatesAreCollapsedAndSorted() throws {
        let data = Data(#"{"catalog":[{"slug":"github","name":"GitHub","connected":true,"noAuth":false}],"services":[{"slug":"github","name":"GitHub","connected":true},{"slug":"exa","name":"Exa","connected":true}]}"#.utf8)
        let model = try JSONDecoder().decode(ComposioConnectionOverview.self, from: data)
        XCTAssertEqual(model.connectedServices.map(\.slug), ["exa", "github"])
    }
}
