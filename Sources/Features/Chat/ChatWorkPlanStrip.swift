import SwiftUI

/// Строка рабочего плана роли над полем ввода чата (владелец 21.10.2026):
/// «План · Разработчик · 2 из 5 · сейчас: …». Нажатие раскрывает тот же
/// список этапов, что в слоте карточки (`SubtaskWorkPlanView`): синий —
/// в работе, зелёный — выполнено. Галочки владелец не переключает — план
/// ведёт роль инструментом `taskflow_work_plan`. Несколько ролей — по строке
/// на каждую. Плана нет — строки нет.
struct ChatWorkPlanStrip: View {
    let chatID: String
    let members: [RoleChatMember]
    /// Растёт, когда сервер прислал `chat:work_plan` или новое сообщение.
    let revision: Int

    @State private var plans: [ChatWorkPlan] = []
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            ForEach(plans) { plan in
                row(plan)
                if expanded.contains(plan.roleID) { items(plan) }
                TFDivider()
            }
        }
        .task(id: "\(chatID):\(revision)") { await load() }
    }

    private func name(_ roleID: String) -> String {
        members.first { $0.id == roleID }?.name ?? "Роль"
    }

    private func row(_ plan: ChatWorkPlan) -> some View {
        let isOpen = expanded.contains(plan.roleID)
        return Button {
            withAnimation(TFMotion.standard) {
                if isOpen { expanded.remove(plan.roleID) } else { expanded.insert(plan.roleID) }
            }
        } label: {
            HStack(spacing: TFSpacing.sm) {
                Image(systemName: plan.doneCount == plan.items.count ? "checkmark.square.fill" : "checklist")
                    .foregroundStyle(plan.doneCount == plan.items.count ? Color.tfGreen : Color.tfBlue)
                    .accessibilityHidden(true)
                Text(summary(plan))
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: isOpen ? "chevron.down" : "chevron.up")
                    .tfText(.meta)
                    .foregroundStyle(Color.tfDim)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("План: \(name(plan.roleID)), выполнено \(plan.doneCount) из \(plan.items.count)")
        .accessibilityValue(isOpen ? "Раскрыто" : "Свёрнуто")
        .accessibilityIdentifier("chat.workPlan.\(plan.roleID)")
    }

    private func summary(_ plan: ChatWorkPlan) -> String {
        var text = "План · \(name(plan.roleID)) · \(plan.doneCount) из \(plan.items.count)"
        if let current = plan.current { text += " · сейчас: \(current.title)" }
        return text
    }

    private func items(_ plan: ChatWorkPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(plan.items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: item.state.symbol)
                        .foregroundStyle(item.state == .done ? Color.tfGreen : (item.state == .inProgress ? Color.tfBlue : Color.tfSub))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).foregroundStyle(Color.tfText)
                        if item.state == .inProgress {
                            Text("Сейчас").tfText(.meta).foregroundStyle(Color.tfBlue)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.title)
                .accessibilityValue(item.state.label)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.bottom, TFSpacing.md)
    }

    private func load() async {
        guard let response: ChatWorkPlansResponse = try? await APIClient().request(.get, "/chats/\(chatID)/work-plans"),
              !Task.isCancelled else { return }
        if response.plans != plans { plans = response.plans }
    }
}
