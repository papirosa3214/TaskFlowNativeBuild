import Foundation
import XCTest
@testable import TaskFlow

/// Итог карточки — форма ответа `GET /api/tasks/:id/outcome`
/// (server/src/lib/taskOutcome.ts), снята с живого T05 01.10.2026.
final class TaskOutcomeTests: XCTestCase {
    static let json = #"""
    {"verdict":{"verdict":"approved","findings":"## Сводка\nВсё подтверждено.","reviewer_id":"role_critic_verifier","created_at":"2026-09-30 10:12:34"},
     "nodes":[{"slot_key":"analysis","role":"analyst","title":"Требования и критерии","result":"Согласован DAG T05","done":1},
              {"slot_key":"executor","role":"builder","title":"Реализация","result":null,"done":false}],
     "documents":[{"id":"n1","title":"Итог: T05","updated_at":"2026-09-30 10:20:00","is_outcome":true},
                  {"id":"n2","title":"DAG T05 — контракт","updated_at":null,"is_outcome":false}],
     "branch":{"name":"roles/2b2638a2","commit":"a5de2628","subject":"feat(plans): T05","ahead":1}}
    """#

    func testDecodesServerShape() throws {
        let outcome = try JSONDecoder().decode(ApiTaskOutcome.self, from: Data(Self.json.utf8))
        XCTAssertEqual(outcome.verdict?.title, "принято")
        XCTAssertNotNil(outcome.verdict?.createdDate)
        XCTAssertEqual(outcome.nodes.map(\.done), [true, false])
        XCTAssertEqual(outcome.documents.first?.isOutcome, true)
        XCTAssertEqual(outcome.branch?.commit, "a5de2628")
        XCTAssertFalse(outcome.isEmpty)
    }

    func testEmptyOutcomeHidesSection() throws {
        let outcome = try JSONDecoder().decode(ApiTaskOutcome.self, from: Data(#"{"verdict":null,"nodes":[],"documents":[],"branch":null}"#.utf8))
        XCTAssertTrue(outcome.isEmpty)
    }
    func testSubtaskResultsAloneDoNotShowOutcomeSection() throws {
        let data = Data(#"{"nodes":[{"title":"Шаг","result":"Полный ответ","done":true}],"documents":[]}"#.utf8)
        let outcome = try JSONDecoder().decode(ApiTaskOutcome.self, from: data)
        XCTAssertTrue(outcome.isEmpty)
        XCTAssertEqual(outcome.nodes.first?.result, "Полный ответ", "Полный ответ сохраняется")
    }

    func testStandaloneOutcomeContentRemainsVisible() throws {
        for fragment in [
            #""verdict":{"verdict":"approved","findings":"Итог","reviewer_id":"r","created_at":"2026-10-29 10:00:00"}"#,
            #""branch":{"name":"main","commit":"abc","subject":"Готово","ahead":1}"#,
            #""documents":[{"id":"n","title":"Итог задачи","is_outcome":true}]"#
        ] {
            let base = fragment.hasPrefix("\"documents") ? #"{"nodes":[],"# : #"{"nodes":[],"documents":[],"#
            let outcome = try JSONDecoder().decode(ApiTaskOutcome.self, from: Data((base + fragment + "}").utf8))
            XCTAssertFalse(outcome.isEmpty, fragment)
        }
    }

}
