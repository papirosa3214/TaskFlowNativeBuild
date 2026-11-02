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
    var loaded = false
    var loading = false
    var error: String?
    /// Сервер без контрактов (старая выкладка .110): маршрута нет. Это не
    /// поломка — экран должен сказать об этом словами, а не ошибкой.
    var unsupported = false

    private let api = APIClient()

    func load(taskID: String) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
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

    var body: some View {
        List {
            controlSection
            visibilitySection
            if model.unsupported {
                Section {
                    Text("Сервер пока не знает про контракт миссий")
                        .tfText(.body)
                        .accessibilityIdentifier("mission.unsupported")
                    Text("Обновите TaskFlow на .110 — после выкладки экран покажет контракт задачи.")
                        .tfText(.meta)
                }
            }
            if let error = model.error {
                Section {
                    Text(error)
                        .tfText(.body)
                        .accessibilityIdentifier("mission.error")
                    Button("Обновить") { Task { await model.load(taskID: taskID) } }
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
                            .tfText(.meta)
                    }
                }
                if showContexts { contextsSection }
                if showStreams { streamsSection }
            }
        }
        .tfNativeHeader("Mission Control", displayMode: .inline)
        .hintAnchor(HintAnchorID.missionControlScreen)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
        }
        // Плоский список — как в координации (02.11.2026): без серых подложек.
        .listStyle(.plain)
        .refreshable { await model.load(taskID: taskID) }
        .task { await model.load(taskID: taskID) }
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
        Section("Управление") {
            if let slot = model.executors?.orchestrator.slotId {
                Button {
                    executorSlotID = slot
                } label: {
                    Label("Написать оркестратору", systemImage: "crown")
                }
                .accessibilityIdentifier("mission.orchestrator")
                Text("Оркестратор разложил работу по ролям — решение по задаче за ним.")
                    .tfText(.meta)
            }
            Button {
                Task {
                    if let chat = try? await APIClient().taskTopic(taskID: taskID) {
                        taskChatID = chat.id
                    }
                }
            } label: {
                Label("Переписка по задаче", systemImage: "bubble.left.and.bubble.right")
            }
            .accessibilityIdentifier("mission.task-chat")
        }
    }

    /// Тумблеры: что панель показывает. Один взгляд — и лишнее убрано.
    private var visibilitySection: some View {
        Section("Что показывать") {
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
        Section("Итог по контракту") {
            LabeledContent("Пройдено", value: "\(outcome.passed) из \(outcome.total)")
            if outcome.failed > 0 {
                LabeledContent("Не пройдено", value: "\(outcome.failed)")
                    .foregroundStyle(Color.tfRed)
            }
            if outcome.blocked > 0 {
                LabeledContent("Не проверяется вживую", value: "\(outcome.blocked)")
                    .foregroundStyle(Color.tfOrange)
            }
            if outcome.pending > 0 {
                LabeledContent("Ещё не проверено", value: "\(outcome.pending)")
            }
            LabeledContent("Миссия", value: outcome.closed ? "закрыта" : "открыта")
                .foregroundStyle(outcome.closed ? Color.tfGreen : Color.tfText)
        }
    }

    private var assertionsSection: some View {
        Section("Ассерции") {
            ForEach(model.assertions) { assertion in
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                        Text(assertion.assertionId)
                            .tfText(.meta)
                            .foregroundStyle(Color.tfDim)
                        Spacer(minLength: 0)
                        TFPill(assertion.statusEnum.title, color: color(for: assertion.statusEnum))
                    }
                    Text(assertion.title)
                        .tfText(.body)
                    Text(assertion.behavior)
                        .tfText(.meta)
                    if let tool = assertion.tool {
                        Text("Проверка: \(tool)")
                            .tfText(.meta)
                            .foregroundStyle(Color.tfDim)
                    }
                    if let slot = assertion.claimedBySlot {
                        Text("Закрыл шаг: \(slot)")
                            .tfText(.meta)
                            .foregroundStyle(Color.tfDim)
                    }
                }
                .padding(.vertical, TFSpacing.xs)
            }
        }
    }

    private func coverageSection(_ coverage: AssertionCoverage) -> some View {
        Section("Дыры в покрытии") {
            ForEach(coverage.violations, id: \.message) { violation in
                Text(violation.message)
                    .tfText(.body)
                    .foregroundStyle(Color.tfRed)
            }
        }
    }

    private var skillsSection: some View {
        Section("Навыки миссии") {
            ForEach(model.skills) { skill in
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    Text(skill.name)
                        .tfText(.body)
                    Text(skill.description)
                        .tfText(.meta)
                    Text("Роль: \(skill.role)")
                        .tfText(.meta)
                        .foregroundStyle(Color.tfDim)
                }
                .padding(.vertical, TFSpacing.xs)
            }
        }
    }

    private var eventsSection: some View {
        Section("Журнал миссии") {
            if model.events.isEmpty {
                Text("Событий пока нет").tfText(.meta)
            }
            ForEach(model.events) { event in
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    Text(event.kindTitle)
                        .tfText(.body)
                    Text(event.ts)
                        .tfText(.meta)
                        .foregroundStyle(Color.tfDim)
                }
                .padding(.vertical, TFSpacing.xs)
            }
        }
    }

    /// Кто чем занимается: роль, состояние, чего ждёт и что она последнее
    /// писала по своему шагу. Тап открывает окно исполнителя.
    private var contextsSection: some View {
        Section("Кто чем занимается") {
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
                                .tfText(.meta)
                            if !executor.waitingFor.isEmpty {
                                Text("Ожидает: " + executor.waitingFor.joined(separator: ", "))
                                    .tfText(.meta)
                                    .foregroundStyle(Color.tfDim)
                            }
                            if let last = executor.messages.first(where: { !$0.isFromOwner }) {
                                Text(last.text)
                                    .tfText(.meta)
                                    .foregroundStyle(Color.tfDim)
                                    .lineLimit(3)
                            }
                        }
                    }
                    .accessibilityIdentifier("mission.executor.\(executor.subtaskId)")
                }
            } else {
                Text("Исполнители не найдены").tfText(.meta)
            }
        }
    }

    /// Потоки: последние сообщения темы задачи — что говорят роли и что
    /// отвечает владелец.
    private var streamsSection: some View {
        Section("Потоки переписки") {
            if model.streams.isEmpty {
                Text("Сообщений пока нет").tfText(.meta)
            }
            ForEach(model.streams) { message in
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.fromUserName ?? "Роль")
                        .tfText(.meta)
                        .foregroundStyle(Color.tfDim)
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
