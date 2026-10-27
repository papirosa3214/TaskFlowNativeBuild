import Foundation
import XCTest
#if canImport(TaskFlow)
@testable import TaskFlow
#endif

final class AgentComponentTests: XCTestCase {
    func testRegistryKnowsWidgetAndEnvelopeNames() {
        XCTAssertEqual(AgentComponentRegistry.kind(for: "weather"), .weather)
        XCTAssertEqual(AgentComponentRegistry.kind(for: "compare"), .compare)
        XCTAssertEqual(AgentComponentRegistry.kind(for: "heading"), .heading)
        XCTAssertEqual(AgentComponentRegistry.kind(for: "html"), .html)
    }

    func testSharedNamesAreOneEntry() {
        // progress и chart — одно имя и в ```widget, и в tf-json.
        XCTAssertEqual(AgentComponentRegistry.kind(for: "progress"), .progress)
        XCTAssertEqual(AgentComponentRegistry.kind(for: "chart"), .chart)
    }

    func testUnknownNameIsNil() {
        XCTAssertNil(AgentComponentRegistry.kind(for: "hologram"))
        XCTAssertNil(AgentComponentRegistry.kind(for: ""))
    }

    func testDecodesComponent() throws {
        let json = #"{"name":"metrics","props":{"type":"metrics","items":[{"label":"a","value":1}]}}"#
        let component = try JSONDecoder().decode(AgentComponent.self, from: Data(json.utf8))
        XCTAssertEqual(component.name, "metrics")
        XCTAssertEqual(component.kind, .metrics)
        let props = try XCTUnwrap(component.propsJSON)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(props.utf8)) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "metrics")
    }
}
