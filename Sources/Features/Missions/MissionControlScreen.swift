import SwiftUI
import Observation

/// Стор экрана Mission Control. Данные — контракт ассерций карточки, журнал
/// прохождения и навыки миссии (сервер .110, миграции 189–191), а сверху —
/// панель управления: написать оркестратору, открыть переписку, посмотреть,
/// кто чем занимается (владелец 02.11.2026: «не я по чатам бегаю, а оркестратор
/// решает»).
@MainActor @Observable
final class MissionControlModel {
    var assertions: [MissionAssertion] = []
    var outcome: MissionOutcome?
    var events: [MissionEvent] = []
    var skills: [MissionSkill] = []
    var coverage: AssertionCoverage?
    /// Сводка по исполнителям: кто чем занимается, чего ждёт, к кому можно
    /// обратиться (`GET /api/coordination/tasks/:id/executors`).
    var executors: TaskExecutorSummary?
    /// Потоки: последние сообщения темы задачи.
    var streams: [RoleChatMessage] = []
    /// Этапы плана: вся работа, которую разложил оркестратор.
    let board = CoordinationBoardModel()
    var loaded = false
    var loading = false
    var error: String?
    /// Сервер без контрактов (старая выкладка .110): маршрута нет. Это не
    /// поломка — экран должен сказать об этом словами, а не ошибкой.
    var unsupported = false

    private let api = APIClient()

    func load(taskID: String, isOwner: Bool) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        await board.load(taskID: taskID, isOwner: isOwner)
        do {
            let contract = try await api.missionContract(taskID: taskID)
            assertions = contract.assertions
            outcome = contract.outcome
            events = (try? await api.missionEvents(taskID: taskID)) ?? []
            skills = (try? await api.missionSkills(taskID: taskID)) ?? []
            coverage = await loadCoverage(taskID: taskID)
            error = nil
        } catch {
            if case APIError.routeMissing = error {
                unsupported = true
                assertions = []
                outcome = nil
            } else {
                self.error = error.localizedDescription
            }
        }
        // Панель управления нужна и без контракта ассерций: сводка
        // исполнителей и потоки живут отдельными маршрутами.
        executors = try? await api.taskExecutorSummary(taskId: taskID)
        streams = await loadStreams(taskID: taskID)
        loaded = true
    }

    /// Покрытие считается по плану задачи: без плана считать нечего.
    private func loadCoverage(taskID: String) async -> AssertionCoverage? {
        guard let plan = try? await api.collaborationPlans(taskId: taskID).first else { return nil }
        return try? await api.assertionCoverage(taskID: taskID, planID: plan.id)
    }

    /// Последние сообщения темы задачи — поток, где видно ответы ролей.
    private func loadStreams(taskID: String) async -> [RoleChatMessage] {
        guard let chat = try? await api.taskTopic(taskID: taskID) else { return [] }
        let messages = (try? await api.roleChatMessages(id: chat.id, projection: .list)) ?? []
        return messages
            .sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
            .suffix(15)
            .map { $0 }
    }
}

/// Mission Control — панель управления миссией: что считается готовым по
/// контракту, что не пройдено, что происходило, кто чем занимается и как
/// вмешаться.
///
/// Наблюдательный экран: контракт здесь не пишется и не правится. Пишет его
/// владелец или оркестратор через API.
struct MissionControlScreen: View {
    let taskID: String
    @State private var model = MissionControlModel()
    @Environment(\.dismiss) private var dismiss
    /// Что показывать в панели. Сохраняется на устройстве: каждый раз заново
    /// расставлять галочки — не работа.
    @AppStorage("mission.showStreams") private var showStreams = true
    @AppStorage("mission.showContexts") private var showContexts = true
    @State private var executorSlotID: String?
    @State private var taskChatID: String?
    @State private var stageSlot: String?
    @Environment(SessionStore.self) private var session

    private var isOwner: Bool { session.currentUser?.role == .owner }

    var body: some View {
        List {
            controlSection
            workSection
            visibilitySection
            if model.unsupported {
                Section {
                    Text("Сервер пока не знает про контракт миссий")
                        .tfText(.body)
                        .accessibilityIdentifier("mission.unsupported")
                    Text("Обновите TaskFlow на .110 — после выкладки экран покажет контракт задачи.")
                        .tfText(.action)
                }
            }
            if let error = model.error {
                Section {
                    Text(error)
                        .tfText(.body)
                        .accessibilityIdentifier("mission.error")
                    TFActionRow(title: "Обновить", icon: "arrow.clockwise") {
                        Task { await model.load(taskID: taskID, isOwner: isOwner) }
                    }
                }
            }
            if model.loading && !model.loaded {
                Section { TFLoading(.inline) }
            }
            if model.loaded && model.error == nil && !model.unsupported {
                if let outcome = model.outcome, outcome.hasContract {
                    summarySection(outcome)
                    assertionsSection
                    if let coverage = model.coverage, !coverage.violations.isEmpty {
                        coverageSection(coverage)
                    }
                    if !model.skills.isEmpty { skillsSection }
                    eventsSection
                } else {
                    Section {
                        Text("У задачи нет контракта ассерций")
                            .tfText(.body)
                            .accessibilityIdentifier("mission.no-contract")
                        Text("Пока контракта нет, «готово» значит «критик посмотрел и одобрил» — критерии подгоняются под получившееся. Контракт фиксирует критерии до работы, и непроверенное «готово» больше не проходит.")
                            .tfText(.action)
                    }
                }
                if showContexts { contextsSection }
                if showStreams { streamsSection }
            }
        }
        .tfScreenBackground()
        .tfNativeHeader("Mission Control", displayMode: .inline)
        .hintAnchor(HintAnchorID.missionControlScreen)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
        }
        // Плоский список — как в координации (02.11.2026): без серых подложек.
        .listStyle(.plain)
        .refreshable { await model.load(taskID: taskID, isOwner: isOwner) }
        .task { await model.load(taskID: taskID, isOwner: isOwner) }
        .sheet(isPresented: Binding(
            get: { stageSlot != nil },
            set: { if !$0 { stageSlot = nil } }
        )) {
            if let stageSlot {
                CoordinationStageSheet(taskID: taskID, slot: stageSlot, model: model.board, editable: false)
            }
        }
        .sheet(isPresented: Binding(
            get: { executorSlotID != nil },
            set: { if !$0 { executorSlotID = nil } }
        )) {
            if let executorSlotID {
                ExecutorWindow(taskID: taskID, subtaskID: executorSlotID)
            }
        }
        .sheet(isPresented: Binding(
            get: { taskChatID != nil },
            set: { if !$0 { taskChatID = nil } }
        )) {
            if let taskChatID { TaskChatSheet(chatID: taskChatID) }
        }
    }

    // MARK: - Панель управления

    /// Управление — сверху, до всего остального: сюда владелец приходит
    /// вмешаться, а не читать отчёт.
    private var controlSection: some View {
        TFPlainSection("Управление") {
            if let slot = model.executors?.orchestrator.slotId {
                TFActionRow(title: "Написать оркестратору", icon: "crown") {
                    executorSlotID = slot
                }
                .accessibilityIdentifier("mission.orchestrator")
                Text("Оркестратор разложил работу по ролям — решение по задаче за ним.")
                    .tfText(.action)
            }
            TFActionRow(title: "Переписка по задаче", icon: "bubble.left.and.bubble.right") {
                Task {
                    if let chat = try? await APIClient().taskTopic(taskID: taskID) {
                        taskChatID = chat.id
                    }
                }
            }
            .accessibilityIdentifier("mission.task-chat")
        }
    }

    /// Масштаб миссии: все этапы, которые разложил оркестратор, и сколько закрыто.
    /// Полотно только для чтения: решения по составу работы за оркестратором.
    @ViewBuilder
    private var workSection: some View {
        if let plan = model.board.plan {
            TFPlainSection("Вся работа") {
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    let stages = model.board.orderedStages.filter { !$0.isSkipped }
                    Text("Сделано \(stages.filter(\.isDone).count) из \(stages.count)")
                        .tfText(.body)
                        .foregroundStyle(Color.tfText)
                    Text("В работе \(stages.filter(\.isActive).count), ждут вас \(stages.filter(\.needsOwner).count)")
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                }
                .listRowSeparator(.hidden)
                CoordinationBoardView(plan: plan, model: model.board, editable: false,
                                      onSelect: { stageSlot = $0 }, onAdd: { _ in })
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
        }
    }

    /// Тумблеры: что панель показывает. Один взгляд — и лишнее убрано.
    private var visibilitySection: some View {
        TFPlainSection("Что показывать") {
            TFListRow(
                icon: "text.bubble", iconStyle: .plain, title: "Потоки переписки",
                trailing: AnyView(
                    TFToggle(isOn: $showStreams)
                        .accessibilityLabel("Потоки переписки")
                        .accessibilityIdentifier("mission.toggle.streams")
                ),
                titleStyle: .action,
                verticalPadding: TFSpacing.xs
            )
            TFListRow(
                icon: "person.2", iconStyle: .plain, title: "Кто чем занимается",
                trailing: AnyView(
                    TFToggle(isOn: $showContexts)
                        .accessibilityLabel("Кто чем занимается")
                        .accessibilityIdentifier("mission.toggle.contexts")
                ),
                titleStyle: .action,
                verticalPadding: TFSpacing.xs
            )
        }
    }

    // MARK: - Секции

    private func summarySection(_ outcome: MissionOutcome) -> some View {
        TFPlainSection("Итог по контракту") {
            TFInfoRow(label: "Пройдено", value: "\(outcome.passed) из \(outcome.total)")
            if outcome.failed > 0 {
                TFInfoRow(label: "Не пройдено", value: "\(outcome.failed)", valueColor: .tfRed)
            }
            if outcome.blocked > 0 {
                TFInfoRow(label: "Не проверяется вживую", value: "\(outcome.blocked)", valueColor: .tfOrange)
            }
            if outcome.pending > 0 {
                TFInfoRow(label: "Ещё не проверено", value: "\(outcome.pending)")
            }
            TFInfoRow(label: "Миссия", value: outcome.closed ? "закрыта" : "открыта",
                                valueColor: outcome.closed ? .tfGreen : .tfText)
        }
    }

    private var assertionsSection: some View {
        TFPlainSection("Ассерции") {
            ForEach(model.assertions) { assertion in
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                        Text(assertion.assertionId)
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                        Spacer(minLength: 0)
                        TFPill(assertion.statusEnum.title, color: color(for: assertion.statusEnum))
                    }
                    Text(assertion.title)
                        .tfText(.body)
                    Text(assertion.behavior)
                        .tfText(.action)
                    if let tool = assertion.tool {
                        Text("Проверка: \(tool)")
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                    }
                    if let slot = assertion.claimedBySlot {
                        Text("Закрыл шаг: \(slot)")
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                    }
                }
                .padding(.vertical, TFSpacing.xs)
            }
        }
    }

    private func coverageSection(_ coverage: AssertionCoverage) -> some View {
        TFPlainSection("Дыры в покрытии") {
            ForEach(coverage.violations, id: \.message) { violation in
                Text(violation.message)
                    .tfText(.body)
                    .foregroundStyle(Color.tfRed)
            }
        }
    }

    private var skillsSection: some View {
        TFPlainSection("Навыки миссии") {
            ForEach(model.skills) { skill in
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    Text(skill.name)
                        .tfText(.body)
                    Text(skill.description)
                        .tfText(.action)
                    Text("Роль: \(skill.role)")
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                }
                .padding(.vertical, TFSpacing.xs)
            }
        }
    }

    private var eventsSection: some View {
        TFPlainSection("Журнал миссии") {
            if model.events.isEmpty {
                Text("Событий пока нет").tfText(.action)
            }
            ForEach(model.events) { event in
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    Text(event.kindTitle)
                        .tfText(.body)
                    Text(event.ts)
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                }
                .padding(.vertical, TFSpacing.xs)
            }
        }
    }

    /// Кто чем занимается: роль, состояние, чего ждёт и что она последнее
    /// писала по своему шагу. Тап открывает окно исполнителя.
    private var contextsSection: some View {
        TFPlainSection("Кто чем занимается") {
            if let executors = model.executors?.executors, !executors.isEmpty {
                ForEach(executors) { executor in
                    Button {
                        executorSlotID = executor.subtaskId
                    } label: {
                        VStack(alignment: .leading, spacing: TFSpacing.xs) {
                            HStack(spacing: TFSpacing.sm) {
                                Text(executor.roleTitle ?? "Роль не назначена")
                                    .tfText(.body)
                                Spacer(minLength: 0)
                                TFPill(executor.stateTitle, color: executor.stateTint)
                            }
                            Text(executor.statusText)
                                .tfText(.action)
                            if !executor.waitingFor.isEmpty {
                                Text("Ожидает: " + executor.waitingFor.joined(separator: ", "))
                                    .tfText(.action)
                                    .foregroundStyle(Color.tfSub)
                            }
                            if let last = executor.messages.first(where: { !$0.isFromOwner }) {
                                Text(last.text)
                                    .tfText(.action)
                                    .foregroundStyle(Color.tfSub)
                                    .lineLimit(3)
                            }
                        }
                    }
                    .accessibilityIdentifier("mission.executor.\(executor.subtaskId)")
                }
            } else {
                Text("Исполнители не найдены").tfText(.action)
            }
        }
    }

    /// Потоки: последние сообщения темы задачи — что говорят роли и что
    /// отвечает владелец.
    private var streamsSection: some View {
        TFPlainSection("Потоки переписки") {
            if model.streams.isEmpty {
                Text("Сообщений пока нет").tfText(.action)
            }
            ForEach(model.streams) { message in
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.fromUserName ?? "Роль")
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                    Text(message.text)
                        .tfText(.body)
                        .lineLimit(8)
                }
                .padding(.vertical, TFSpacing.xs)
            }
        }
    }

    private func color(for status: MissionAssertionStatus) -> Color {
        switch status {
        case .pending: return .tfDim
        case .passed: return .tfGreen
        case .failed: return .tfRed
        case .blocked: return .tfOrange
        }
    }
}
