import SwiftUI

struct AgentStatusGrid: View {
    @Environment(TaskStore.self) private var taskStore
    var body: some View {
        HStack(spacing: 8) {
            statusTile(route: .agentWork(focus: .inProgress), title: "В работе", count: workingCount, kind: .running)
            statusTile(route: .agentWork(focus: .review), title: "На проверке", count: reviewCount, kind: .review)
            statusTile(route: .agentWork(focus: .blocked), title: "Заблокированы", count: blockedCount, kind: .blocked)
            statusTile(route: .agentWork(focus: .stale), title: "Пропали", count: staleCount, kind: .stale)
        }
    }
    private func statusTile(route: AppRoute, title: String, count: Int, kind: ProjectStatusIcon.Kind) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 8) {
                ProjectStatusIcon(kind: kind)
                Text("\(count)").monospacedDigit().foregroundStyle(Color.tfText)
            }.frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(count)")
        .accessibilityIdentifier("projects.status.\(title)")
    }

    private var workingCount: Int {
        taskStore.agentWorkTasks.count { $0.status == .active && $0.agentState == .inProgress && $0.agentStale != true }
    }
    private var reviewCount: Int {
        taskStore.agentWorkTasks.count { $0.status == .active && $0.agentState == .review }
    }
    private var blockedCount: Int {
        taskStore.agentWorkTasks.count { $0.status == .active && $0.agentState == .blocked }
    }
    private var staleCount: Int {
        taskStore.agentWorkTasks.count { $0.status == .active && $0.agentState == .inProgress && $0.agentStale == true }
    }
}

struct ProjectStatusIcon: View {
    enum Kind { case running, review, blocked, stale }
    let kind: Kind
    var body: some View {
        Group {
            switch kind {
            case .running: TFSubtaskStatusRing(.running)
            case .review: TFSubtaskStatusRing(.review)
            case .blocked: TFSubtaskStatusRing(.blocked)
            case .stale:
                ZStack {
                    Image(systemName: "triangle").font(.system(size: 21))
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).offset(y: 2)
                }.foregroundStyle(Color.tfRed)
            }
        }.frame(width: 21, height: 21).accessibilityHidden(true)
    }
}
