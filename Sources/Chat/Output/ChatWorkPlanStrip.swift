import SwiftUI

/// Строка рабочего плана роли над полем ввода чата (владелец 21.10.2026):
/// «План · Разработчик · 2 из 5 · сейчас: …». Нажатие раскрывает тот же
/// список этапов, что в слоте карточки (`SubtaskWorkPlanView`): синий —
/// в работе, зелёный — выполнено. Галочки владелец не переключает — план
/// ведёт роль инструментом `taskflow_work_plan`.
///
/// С 25.10.2026 (карточка b504958a) состояние пункта — серверное: кроме
/// «сейчас» и «выполнено» есть заблокированный пункт с причиной и остановка
/// плана. Клиент ничего не додумывает: что пришло, то и нарисовано.
/// Несколько ролей — по строке на каждую. Плана нет — строки нет.
struct ChatWorkPlanStrip: View {
    let chatID: String
    let members: [RoleChatMember]
    /// Растёт, когда сервер прислал новое сообщение.
    let revision: Int
    /// Последнее событие `chat:work_plan`: план берётся прямо из него,
    /// без повторного запроса (27.10.2026).
    var event: JSONValue? = nil

    @State private var plans: [ChatWorkPlan]

    /// Последний план чата в памяти: при повторном открытии строка стоит
    /// сразу, а не выезжает после загрузки и не сдвигает ленту (26.10.2026).
    @MainActor private static var lastPlans: [String: [ChatWorkPlan]] = [:]

    init(chatID: String, members: [RoleChatMember], revision: Int, event: JSONValue? = nil) {
        self.chatID = chatID
        self.members = members
        self.revision = revision
        self.event = event
        _plans = State(initialValue: Self.lastPlans[chatID] ?? [])
    }

    var body: some View {
        ChatWorkPlanRows(plans: plans, members: members, floating: true)
            .task(id: "\(chatID):\(revision)") { await load() }
            .onChange(of: event) { _, event in
                guard let event, let updated = ChatWorkPlan.applyingEvent(event, chatID: chatID, to: plans) else { return }
                Self.lastPlans[chatID] = updated
                if updated != plans { plans = updated }
            }
    }

    private func load() async {
        guard let response: ChatWorkPlansResponse = try? await APIClient().request(.get, "/chats/\(chatID)/work-plans"),
              !Task.isCancelled else { return }
        Self.lastPlans[chatID] = response.plans
        if response.plans != plans { plans = response.plans }
    }
}

/// Сама полоса без запросов: её рисуют и чат, и отладочная галерея кадров.
struct ChatWorkPlanRows: View {
    let plans: [ChatWorkPlan]
    let members: [RoleChatMember]
    /// Развёрнуто сразу — для кадров отладочной галереи; в чате свёрнуто.
    var initiallyExpanded: Bool = false
    /// Висячая карточка над лентой, как пул задач в «Дне» (владелец 28.10.2026):
    /// подложка не до краёв, вокруг неё лента остаётся видна.
    var floating: Bool = false
    @State private var expanded: Set<String> = []

    var body: some View {
        if floating {
            if !plans.isEmpty {
                TFCard(padding: 0, surface: .card, radius: TFRadius.xl) {
                    list(divided: false)
                }
                    .tfShadow(TFShadow.dropdown)
                    .padding(.horizontal, TFSpacing.lg)
                    .padding(.bottom, TFSpacing.sm)
            }
        } else {
            list(divided: true)
        }
    }

    private func list(divided: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(plans.enumerated()), id: \.element.id) { index, plan in
                if !divided && index > 0 { TFDivider() }
                row(plan)
                if expanded.contains(plan.roleID) { items(plan) }
                if divided { TFDivider() }
            }
        }
        .onAppear {
            if initiallyExpanded { expanded = Set(plans.map(\.roleID)) }
        }
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
                Image(systemName: rowSymbol(plan))
                    .foregroundStyle(rowTint(plan))
                    .accessibilityHidden(true)
                Text(plan.summary(roleName: name(plan.roleID)))
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
        .hintAnchor(HintAnchorID.chatWorkPlan)
    }

    private func rowSymbol(_ plan: ChatWorkPlan) -> String {
        if plan.isStopped { return "pause.circle" }
        if plan.doneCount == plan.items.count { return "checkmark.square.fill" }
        return plan.items.contains { $0.state == .blocked } ? "exclamationmark.square.fill" : "checklist"
    }

    private func rowTint(_ plan: ChatWorkPlan) -> Color {
        if plan.isStopped { return Color.tfDim }
        if plan.doneCount == plan.items.count { return Color.tfGreen }
        if plan.items.contains(where: { $0.state == .blocked }) { return Color.tfOrange }
        return Color.tfBlue
    }

    private func items(_ plan: ChatWorkPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(plan.items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: item.state.symbol)
                        .foregroundStyle(tint(item.state))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).foregroundStyle(item.state == .stopped ? Color.tfSub : Color.tfChatText)
                        if let note = item.statusNote {
                            Text(note)
                                .tfText(.meta)
                                .foregroundStyle(tint(item.state))
                                .lineLimit(3)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.title)
                .accessibilityValue([item.state.label, item.statusNote].compactMap { $0 }.joined(separator: ", "))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.bottom, TFSpacing.md)
    }

    /// Цвет состояния — тот же, что в слоте карточки: синий — сейчас,
    /// зелёный — сдано, оранжевый — ждёт, серый — остановлено или впереди.
    private func tint(_ state: SubtaskWorkPlan.Item.State) -> Color {
        switch state {
        case .done: Color.tfGreen
        case .inProgress: Color.tfBlue
        case .blocked: Color.tfOrange
        case .stopped, .pending: Color.tfSub
        }
    }
}

/// Признак доставки под сообщением владельца: «сохранено» и «передано исполнителю» —
/// разные вещи (карточка b504958a), и владелец должен видеть, какая из них.
struct ChatDeliveryBadge: View {
    let state: ChatMessageDeliveryState

    var body: some View {
        TFPill(surface: .clear, radius: 0) {
            HStack(spacing: TFSpacing.xs) {
                Image(systemName: state.symbol)
                    .tfText(.meta)
                    .accessibilityHidden(true)
                Text(state.label).tfText(.meta)
            }
            .foregroundStyle(state.isProblem ? Color.tfOrange : Color.tfDim)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Доставка: \(state.label)")
        .accessibilityIdentifier("chat.delivery.\(state.rawValue)")
    }
}
