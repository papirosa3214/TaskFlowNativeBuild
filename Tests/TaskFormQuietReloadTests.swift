import XCTest
@testable import TaskFlow

/// Тихое обновление открытой карточки не должно откатывать чужие правки
/// (LOCK-TASKFORM-QUIET-RELOAD-20261016): 16.10.2026 карточку дважды
/// возвращало в старый проект автосохранением со старым `projectId`.
@MainActor
final class TaskFormQuietReloadTests: XCTestCase {

    func testUntouchedFieldsFollowServer() {
        let old = TestTaskFactory.makeTask(id: "t1", title: "Виджеты", projectId: "p-server", assigneeId: nil)
        let fresh = TestTaskFactory.makeTask(id: "t1", title: "Виджеты на маке", projectId: "p-ios", assigneeId: "role_builder")
        let viewModel = TaskFormViewModel(taskID: nil, apiClient: APIClient())
        viewModel.title = old.title
        viewModel.projectId = old.projectId
        viewModel.assigneeId = old.assigneeId

        viewModel.adoptServerChanges(from: old, to: fresh)

        XCTAssertEqual(viewModel.projectId, "p-ios")
        XCTAssertEqual(viewModel.title, "Виджеты на маке")
        XCTAssertEqual(viewModel.assigneeId, "role_builder")
    }

    func testOwnerEditInProgressIsKept() {
        let old = TestTaskFactory.makeTask(id: "t1", title: "Виджеты", projectId: "p-server")
        let fresh = TestTaskFactory.makeTask(id: "t1", title: "Виджеты", projectId: "p-ios")
        let viewModel = TaskFormViewModel(taskID: nil, apiClient: APIClient())
        viewModel.title = "Виджеты — пишу сейчас"
        viewModel.projectId = "p-mine"

        viewModel.adoptServerChanges(from: old, to: fresh)

        XCTAssertEqual(viewModel.title, "Виджеты — пишу сейчас")
        XCTAssertEqual(viewModel.projectId, "p-mine")
    }
}
