import Foundation
import Observation

/// One loaded plan snapshot per card, shared by its probe, graph and restored view.
@MainActor
@Observable
public final class CollaborationPlanState {
    var plan: ApiCollaborationPlan?
    var draftPlan: ApiCollaborationPlan?
    var subtasks: [ApiSubtask] = []
    var roleTitles: [String: String] = [:]
    var isVisible = false
    private var loadedToken: Int?
    private struct Request: Equatable {
        let taskID: String
        let reloadToken: Int
        let isOwner: Bool
        let focusChildID: String?
    }
    private var loadingRequest: Request?
    private var pendingRequest: Request?
    private var loadTask: Task<Void, Never>?
    private let api: APIClient

    public init(api: APIClient = APIClient()) { self.api = api }

    func load(taskID: String, reloadToken: Int, force: Bool = false, isOwner: Bool, focusChildID: String? = nil) async {
        guard force || loadedToken != reloadToken else { return }
        let request = Request(taskID: taskID, reloadToken: reloadToken, isOwner: isOwner, focusChildID: focusChildID)
        if let loadTask {
            if force || loadingRequest != request { pendingRequest = request }
            await loadTask.value
            return
        }
        pendingRequest = request
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.loadTask = nil; self.loadingRequest = nil }
            while let next = self.pendingRequest {
                self.pendingRequest = nil
                self.loadingRequest = next
                await self.fetch(next)
            }
        }
        loadTask = task
        await task.value
    }

    private func fetch(_ request: Request) async {
        let taskID = request.taskID
        let focusChildID = request.focusChildID
        let isOwner = request.isOwner
        async let plansRequest = api.collaborationPlans(taskId: taskID)
        async let subtasksRequest = api.subtasks(taskId: taskID)
        async let rolesRequest = api.roles()
        guard let plans = try? await plansRequest else { return }
        let steps = ((try? await subtasksRequest) ?? []).filter { $0.collaborationPlanId != nil }
        let titles = ((try? await rolesRequest) ?? []).reduce(into: [String: String]()) { $0[$1.role] = $1.title }
        // Дочерняя карточка: её собственный план точнее общего плана корня,
        // поэтому он приоритетнее; нет своего — покажем её шаги из плана корня
        // (сам срез делается в графе по `task_id`).
        var ownPlans: [ApiCollaborationPlan] = []
        if let focusChildID, let fetched = try? await api.collaborationPlans(taskId: focusChildID) {
            ownPlans = fetched
        }
        // An unchanged snapshot must not rebuild the graph or its List row.
        let approved = ownPlans.first { $0.status == "approved" } ?? plans.first { $0.status == "approved" }
        let draft = ownPlans.first { $0.status == "draft" } ?? plans.first { $0.status == "draft" }
        if plan != approved { plan = approved }
        if draftPlan != draft { draftPlan = draft }
        if subtasks != steps { subtasks = steps }
        if !titles.isEmpty, roleTitles != titles { roleTitles = titles }
        let visible = approved != nil || (draft != nil && isOwner)
        if isVisible != visible { isVisible = visible }
        loadedToken = request.reloadToken
    }

    func replace(_ updated: ApiCollaborationPlan) {
        if plan?.id == updated.id { plan = updated }
        if draftPlan?.id == updated.id { draftPlan = updated }
    }
}
