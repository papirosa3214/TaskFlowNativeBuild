import SwiftUI

// Строка задачи вида «Список» — spec/SCREENS-1.md §3.3 (`TaskRow.tsx`),
// с проп-переопределением экрана «Планирование»: `maxLabels=1 showDueBadge=false`
// (§5.2). Раз срок никогда не рисуется здесь (и задача никогда не бывает
// просроченной — «Планирование» показывает только due_date ≥ сегодня, §5.2),
// содержимое строки уже покрывает `TFTaskRow` из `DesignSystem` дословно —
// здесь только добавлен свайп (`DesignSystem` его не умеет, см. отчёт).
struct UpcomingTaskRow: View {
    let task: ApiTask
    let onOpen: () -> Void
    let onComplete: () -> Void
    let onDelete: () -> Void

    @State private var confirmDelete = false

    var body: some View {
        swipeBody
        .confirmationDialog("Отправить задачу в архив?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("В архив", role: .destructive, action: onDelete)
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("«\(task.title)» будет отправлена в архив. Её можно восстановить.")
        }
    }

    @ViewBuilder
    private var swipeBody: some View {
            TFTaskRow(Self.model(for: task), action: onOpen)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rowAccessibilityLabel)
                .accessibilityIdentifier("upcoming.task-row")
                .accessibilityAddTraits(.isButton)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("В архив", systemImage: "archivebox")
                    }
                    .tint(Color.tfSwipeDelete)
                    .accessibilityLabel("В архив")
                    .accessibilityIdentifier("row.swipe.delete")
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(action: onComplete) {
                        Label("Завершить", systemImage: "checkmark")
                    }
                    .tint(Color.tfGreen)
                    .accessibilityLabel("Завершить")
                    .accessibilityIdentifier("row.swipe.complete")
                }
    }

    /// Короткое имя для VoiceOver.
    private var rowAccessibilityLabel: String {
        if let projectName = task.projectName, !projectName.isEmpty {
            return "\(projectName), \(task.title)"
        }
        return task.title
    }

    static func model(for task: ApiTask) -> TFTaskRowModel {
        TFTaskRowModel(
            projectName: task.projectName,
            projectColor: task.projectColor.map { Color(hex: $0) },
            assigneeInitials: task.rowAvatarInitials,
            assigneeColor: task.assigneeColor.map { Color(hex: $0) },
            assigneeID: task.rowAvatarID,
            assigneeTeam: task.rowAvatarTeam,
            assigneeAvatarURL: task.rowAvatarURL,
            assigneeTeamURLs: task.rowAvatarTeamURLs,
            assigneePortrait: task.rowAvatarPortrait,
            title: task.title,
            isDone: task.status == .completed,
            description: (task.description?.isEmpty == false) ? task.description : nil,
            agentStatus: UpcomingAgentStateTag.text(task),
            agentStatusColor: UpcomingAgentStateTag.color(task),
            subtasksDone: task.subtasks.isEmpty ? nil : task.subtasks.count { $0.done },
            subtasksTotal: task.subtasks.isEmpty ? nil : task.subtasks.count,
            childrenCount: task.childrenCount,
            hasCollaborationPlan: task.hasCollaborationPlan,
            priority: TaskPriority(rawValue: task.priority),
            isOverdue: false, // «Планирование» никогда не показывает просроченное (спека §5.2)
            dueText: nil,     // showDueBadge=false (спека §5.2)
            labels: task.labels.prefix(1).map { ($0.name, Color(hex: $0.color ?? TFHexDefault.unassigned)) }, // maxLabels=1
            createdAtStamp: task.createdAt // метка даты заведения (LOCK-TASK-CREATED-STAMP)
        )
    }

}

/// Статус агента плоским текстом — spec §3.11 `AgentStateTag` (вариант «plain», без подложки).
enum UpcomingAgentStateTag {
    static func text(_ task: ApiTask) -> String? {
        guard let state = task.listAgentState else { return nil }
        return TFAgentStateTag.text(state, stale: task.agentStale == true)
    }

    static func color(_ task: ApiTask) -> Color {
        guard let state = task.listAgentState else { return .tfTeal }
        return TFAgentStateTag.color(state, stale: task.agentStale == true)
    }
}
