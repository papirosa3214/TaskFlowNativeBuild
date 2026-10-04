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
    private var isLoading = false
    private let api: APIClient

    public init(api: APIClient = APIClient()) { self.api = api }

    func load(taskID: String, reloadToken: Int, force: Bool = false, isOwner: Bool) async {
        guard !isLoading, force || loadedToken != reloadToken else { return }
        isLoading = true
        defer { isLoading = false }
        async let plansRequest = api.collaborationPlans(taskId: taskID)
        async let subtasksRequest = api.subtasks(taskId: taskID)
        async let rolesRequest = api.roles()
        guard let plans = try? await plansRequest else { return }
        let steps = ((try? await subtasksRequest) ?? []).filter { $0.collaborationPlanId != nil }
        let titles = ((try? await rolesRequest) ?? []).reduce(into: [String: String]()) { $0[$1.role] = $1.title }
        // Unchanged polling responses must not rebuild the graph or its List row.
        let approved = plans.first { $0.status == "approved" }
        let draft = plans.first { $0.status == "draft" }
        if plan != approved { plan = approved }
        if draftPlan != draft { draftPlan = draft }
        if subtasks != steps { subtasks = steps }
        if !titles.isEmpty, roleTitles != titles { roleTitles = titles }
        let visible = approved != nil || (draft != nil && isOwner)
        if isVisible != visible { isVisible = visible }
        loadedToken = reloadToken
    }

    func replace(_ updated: ApiCollaborationPlan) {
        if plan?.id == updated.id { plan = updated }
        if draftPlan?.id == updated.id { draftPlan = updated }
    }
}
