import XCTest
@testable import TaskFlow

@MainActor
final class TaskArchiveTests: XCTestCase {
    private let active = #"{"id":"archive-test","title":"Test","status":"active","labels":[],"subtasks":[]}"#
    private let archived = #"{"id":"archive-test","title":"Test","status":"active","archived_at":"2026-10-08 08:00:00","labels":[],"subtasks":[]}"#
    private func api() -> APIClient {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [ArchiveURLProtocol.self]
        return APIClient(session: URLSession(configuration: c))
    }
    override func tearDown() { ArchiveURLProtocol.handler = nil }
    func testDeleteUsesArchivePostAndMovesCardToArchive() async throws {
        var didArchive = false
        ArchiveURLProtocol.handler = { r in
            if r.httpMethod == "POST" { XCTAssertEqual(r.url?.path, "/api/tasks/archive-test/archive"); didArchive = true; return (200, Data("{\"task\":\(self.archived)}".utf8)) }
            let isArchive = URLComponents(url:r.url!,resolvingAgainstBaseURL:false)?.queryItems?.contains { $0.name == "archived" && $0.value == "true" } == true
            return (200, Data((isArchive ? (didArchive ? "[\(self.archived)]" : "[]") : (didArchive ? "[]" : "[\(self.active)]")).utf8))
        }
        let store = TaskStore(apiClient:api());await store.load()
        XCTAssertEqual(store.tasks.count,1)
        let ok = await store.delete(taskId:"archive-test")
        XCTAssertTrue(ok);XCTAssertTrue(store.tasks.isEmpty);XCTAssertEqual(store.archivedTasks.first?.id,"archive-test")
    }
    func testPermanentDeleteRequiresArchiveAndAcceptsDeletedResponse() async {
        var deleted = false
        ArchiveURLProtocol.handler = { r in
            if r.httpMethod == "DELETE" { deleted = true; return (200,Data(#"{"deleted":true,"task_id":"archive-test","counts":{}}"#.utf8)) }
            return (200,Data((deleted ? "[]" : "[\(self.archived)]").utf8))
        }
        let store = TaskStore(apiClient:api())
        let refused = await store.permanentlyDelete(taskId:"archive-test")
        XCTAssertFalse(refused);XCTAssertFalse(deleted)
        await store.loadArchive()
        let ok = await store.permanentlyDelete(taskId:"archive-test")
        XCTAssertTrue(ok);XCTAssertTrue(deleted);XCTAssertTrue(store.archivedTasks.isEmpty)
    }
    /// Восстановление выполненной задачи не возвращает её в живые списки.
    ///
    /// Модель владельца 01.11.2026: «в архив уходят отменённые и выполненные…
    /// Из всех остальных списков убрать». Выполненная задача — закрытая, она
    /// не живая: после `restore` её нет ни в `store.tasks`, ни в
    /// `store.agentWorkTasks`. Ожидание «восстановленная задача вернулась в
    /// `store.tasks` со статусом completed» было написано под старую модель
    /// и противоречило нынешней.
    func testRestoreKeepsCompletedTaskOutOfLiveListsAndRejectsServerFailure() async throws {
        var restored = false
        ArchiveURLProtocol.handler = { r in
            if r.httpMethod == "POST" { XCTAssertEqual(r.url?.path,"/api/tasks/archive-test/restore");restored=true;return (200,Data(#"{"task":{"id":"archive-test","title":"Test","status":"completed","archived_at":null,"labels":[],"subtasks":[]}}"#.utf8)) }
            let isArchive = r.url?.query?.contains("archived=true") == true
            return (200,Data((isArchive ? (restored ? "[]" : "[\(self.archived)]") : (restored ? "[\(self.active.replacingOccurrences(of:"active",with:"completed"))]" : "[]")).utf8))
        }
        let store=TaskStore(apiClient:api());await store.loadArchive()
        let ok=await store.restore(taskId:"archive-test")
        XCTAssertTrue(ok)
        XCTAssertTrue(store.archivedTasks.isEmpty)
        // Выполненная задача закрыта — в живых списков её нет.
        XCTAssertTrue(store.tasks.isEmpty)
        XCTAssertTrue(store.agentWorkTasks.isEmpty)
        XCTAssertFalse(store.tasks.contains { $0.id == "archive-test" })
        // Сбой сервера на удалении: операция не проходит, живые списки не меняются.
        ArchiveURLProtocol.handler = { _ in (503,Data(#"{"error":"Unavailable"}"#.utf8)) }
        let failed=await store.delete(taskId:"archive-test")
        XCTAssertFalse(failed)
        XCTAssertTrue(store.tasks.isEmpty)
        XCTAssertEqual(store.agentWorkTasks.count, 0)
    }
    func testProjectPurgeIsAvailableOnlyAfterLoadingArchive() async {
        var requests: [String] = []
        ArchiveURLProtocol.handler = { r in
            requests.append("\(r.httpMethod ?? "GET") \(r.url!.path)")
            if r.httpMethod == "DELETE" { return (200, Data(#"{"ok":true,"purged":true}"#.utf8)) }
            return (200, Data(#"[{"id":"project-test","name":"Archived project","task_count":2}]"#.utf8))
        }
        let store = ProjectStore(apiClient: api())
        let refused = await store.purgeArchived(projectId: "project-test")
        XCTAssertFalse(refused); XCTAssertTrue(requests.isEmpty)
        await store.loadArchive()
        let ok = await store.purgeArchived(projectId: "project-test")
        XCTAssertTrue(ok)
        XCTAssertTrue(requests.contains("DELETE /api/projects/project-test/purge"))
        XCTAssertFalse(requests.contains("DELETE /api/projects/project-test"))
    }

    func testRealtimeArchiveAndRestoreMoveLists() throws {
        let store=TaskStore(apiClient:api())
        for (type,task) in [("task:archived",archived),("task:restored",active)] {
            let event=try XCTUnwrap(RealtimeEvent.parse(Data("{\"type\":\"\(type)\",\"task\":\(task)}".utf8)))
            store.apply(event)
            XCTAssertEqual(store.archivedTasks.count,type == "task:archived" ? 1 : 0)
            XCTAssertEqual(store.tasks.count,type == "task:restored" ? 1 : 0)
        }
    }
}
private final class ArchiveURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int,Data))?
    override class func canInit(with request:URLRequest)->Bool {true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {
        do { let (status,data)=try XCTUnwrap(Self.handler)(request)
            let response=HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:["Content-Type":"application/json"])!
            client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
        } catch {client?.urlProtocol(self,didFailWithError:error)}
    }
    override func stopLoading() {}
}
