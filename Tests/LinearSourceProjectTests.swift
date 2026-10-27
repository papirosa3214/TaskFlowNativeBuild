import Foundation
import XCTest
#if canImport(TaskFlow)
@testable import TaskFlow
#endif

/// Импорт из Linear: откуда забирать задачи (владелец 27.10.2026).
/// Без проекта — как раньше, все задачи «в работе»; с проектом — его задачи.
final class LinearSourceProjectTests: XCTestCase {
    @objc func testQueryWithoutProjectKeepsOldList() {
        XCTAssertEqual(LinearIssueQuery.items(cursor: nil, projectID: nil), [])
        XCTAssertEqual(LinearIssueQuery.items(cursor: "c2", projectID: nil), [URLQueryItem(name: "cursor", value: "c2")])
    }

    @objc func testQueryWithProjectAddsProjectID() {
        XCTAssertEqual(LinearIssueQuery.items(cursor: nil, projectID: "p1"), [URLQueryItem(name: "project_id", value: "p1")])
        XCTAssertEqual(LinearIssueQuery.items(cursor: "c2", projectID: "p1"),
                       [URLQueryItem(name: "cursor", value: "c2"), URLQueryItem(name: "project_id", value: "p1")])
    }

    @objc func testProjectListDecodes() throws {
        let list = try JSONDecoder().decode(LinearSourceProjectList.self, from: Data(#"{"workspace":{"id":"W","name":"Papirossa"},"projects":[{"id":"p1","name":"TaskFlow (сервер + веб)","state":"started"}]}"#.utf8))
        XCTAssertEqual(list.workspace.id, "W")
        XCTAssertEqual(list.projects.map(\.name), ["TaskFlow (сервер + веб)"])
        XCTAssertEqual(list.projects.first?.id, "p1")
    }

    @objc func testSourceNameFallsBackToAllStarted() {
        let projects = [LinearSourceProject(id: "p1", name: "TaskFlow (iOS)", state: "started")]
        XCTAssertEqual(LinearSourceProject.title(of: "p1", in: projects), "TaskFlow (iOS)")
        XCTAssertEqual(LinearSourceProject.title(of: nil, in: projects), "Все задачи в работе")
        XCTAssertEqual(LinearSourceProject.title(of: "gone", in: projects), "Все задачи в работе")
    }
}
