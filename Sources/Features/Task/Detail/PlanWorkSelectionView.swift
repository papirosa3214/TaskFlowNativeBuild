import SwiftUI

/// Draft work list: choice controls are deliberately separate from completion.
struct PlanWorkSelectionView: View {
    let plan: ApiCollaborationPlan
    let subtasks: [ApiSubtask]
    let roleTitles: [String: String]
    let onUpdated: (ApiCollaborationPlan) -> Void
    @State private var saving = false
    @State private var error: String?
    private var sources: Set<String> { Set(plan.nodes.compactMap(\.sourceSubtaskId)) }

    var body: some View {
        ForEach(subtasks.filter { !sources.contains($0.id) && $0.collaborationPlanId == nil }) { step in
            Text(step.title).font(.body).foregroundStyle(Color.tfText)
        }
        ForEach(plan.nodes.filter { !$0.isSkipped }) { node in
            VStack(alignment: .leading, spacing: 8) {
                if node.requiresChoice == true {
                    if node.workChoice == nil || node.workChoice == "original" {
                        choice(node, text: node.originalTitle ?? "", value: "original", planned: false)
                    }
                    if node.workChoice == nil || node.workChoice == "planned" {
                        choice(node, text: node.plannedWork ?? node.expectedResult, value: "planned", planned: true)
                    }
                    if node.workChoice != nil {
                        Button("Изменить выбор") { save(node, choice: nil) }
                            .buttonStyle(.plain).disabled(saving)
                            .font(.caption).foregroundStyle(Color.tfSub)
                            .accessibilityIdentifier("plan-choice-reset.\(node.slotKey)")
                    }
                } else {
                    Text(node.originalTitle ?? node.plannedWork ?? node.expectedResult)
                        .font(.body).foregroundStyle(Color.tfText)
                }
                HStack(spacing: 6) {
                    TFAvatar(size: .xs, initials: String((roleTitles[node.roleKey] ?? node.roleKey).prefix(1)), userID: "role_" + node.roleKey)
                    Text(roleTitles[node.roleKey] ?? node.roleKey)
                    Text("· Запланировано")
                }.font(.caption).foregroundStyle(Color.tfSub)
            }.padding(.vertical, 4)
        }
        if let error { Text(error).font(.caption).foregroundStyle(Color.tfRed) }
    }

    private func choice(_ node: ApiCollaborationPlanNode, text: String, value: String, planned: Bool) -> some View {
        Button { save(node, choice: value) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: node.workChoice == value ? "checkmark.square" : "square")
                Text(planned ? "По плану: \(text)" : text).multilineTextAlignment(.leading)
            }.font(.body).foregroundStyle(Color.tfText)
        }.buttonStyle(.plain).disabled(saving)
            .accessibilityIdentifier("plan-choice.\(node.slotKey).\(value)")
    }

    private func save(_ node: ApiCollaborationPlanNode, choice: String?) {
        guard !saving else { return }
        saving = true; error = nil
        Task { @MainActor in
            defer { saving = false }
            do { onUpdated(try await APIClient().choosePlanWork(taskId: node.taskId ?? plan.taskId,
                planId: node.sourcePlanId ?? plan.id, slot: node.sourceSlotKey ?? node.slotKey,
                choice: choice, version: node.sourcePlanVersion ?? plan.version ?? 1)) }
            catch { self.error = error.localizedDescription }
        }
    }
}
