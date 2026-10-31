import SwiftUI

/// Читаем план, составленный исполнителем. Галочки владелец не переключает.
struct SubtaskWorkPlanView: View {
    let taskID: String
    let subtaskID: String
    @Environment(RealtimeClient.self) private var realtime
    @Environment(\.scenePhase) private var scenePhase
    @State private var plan: SubtaskWorkPlan?
    @State private var loaded = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let plan, plan.subtaskID == subtaskID {
                Text("Выполнено \(plan.doneCount) из \(plan.items.count)")
                    .tfText(.meta).foregroundStyle(Color.tfSub)
                    .accessibilityIdentifier("work-plan.progress.\(subtaskID)")
                ForEach(plan.items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: item.state.symbol)
                            .foregroundStyle(item.state == .done ? Color.tfGreen : (item.state == .inProgress ? Color.tfBlue : Color.tfSub))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            if item.state == .inProgress {
                                Text("Сейчас").tfText(.meta).foregroundStyle(Color.tfBlue)
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.title)
                    .accessibilityValue(item.state.label)
                    .accessibilityIdentifier("work-plan.item.\(item.id)")
                }
                if failed { Text("Не удалось обновить этапы").tfText(.meta).foregroundStyle(Color.tfSub) }
            } else if loaded {
                Text(failed ? "Не удалось загрузить этапы исполнителя" : "Исполнитель ещё не составил рабочие этапы")
                    .foregroundStyle(Color.tfSub)
            } else {
                ProgressView()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("work-plan.\(subtaskID)")
        .task(id: "\(subtaskID):\(scenePhase):\(realtime.revision(for: taskID))") {
            guard scenePhase == .active else { return }
            do {
                let response: SubtaskWorkPlanResponse = try await APIClient().request(.get, "/subtasks/\(subtaskID)/work-plan")
                try Task.checkCancellation()
                guard response.plan == nil || response.plan?.subtaskID == subtaskID else {
                    failed = true; loaded = true; return
                }
                plan = response.plan; failed = false; loaded = true
            } catch {
                if !Task.isCancelled { failed = true; loaded = true }
            }
        }
    }
}
