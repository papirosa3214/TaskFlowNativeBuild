import SwiftUI
import Observation

/// Данные Mission Control: этапы, сводка исполнителей, контракт, журнал и переписка.
/// По замыслу это показ работы оркестратора и его команды, а не отдельная система
/// (разбор Factory, 01.11.2026). Каждый источник грузится сам: старый сервер или
/// отсутствие контракта не должны гасить весь экран.
@MainActor @Observable
final class MissionControlModel {
    let board = CoordinationBoardModel()
    var assertions: [MissionAssertion] = []
    var outcome: MissionOutcome?
    var events: [MissionEvent] = []
    var skills: [MissionSkill] = []
    var coverage: AssertionCoverage?
    var executors: TaskExecutorSummary?
    var activity: ApiTaskActivity?
    /// Когда получено время миссии: от него тикают секунды идущей работы.
    var timeFetchedAt = Date()
    var loaded = false
    var loading = false
    var error: String?
    /// Сервер без контрактов (старая выкладка .110): маршрута нет. Это не поломка.
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
            if let plan = board.plan {
                coverage = try? await api.assertionCoverage(taskID: taskID, planID: plan.id)
            }
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
        executors = try? await api.taskExecutorSummary(taskId: taskID)
        timeFetchedAt = Date()
        activity = try? await api.taskActivity(taskId: taskID)
        if isOwner { await board.loadContext(taskID: taskID) }
        loaded = true
    }

    func setPaused(_ paused: Bool, taskID: String, isOwner: Bool) async {
        guard let plan = board.plan else { return }
        do {
            try await api.setCollaborationPlanPaused(taskId: taskID, planId: plan.id, paused: paused)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        await load(taskID: taskID, isOwner: isOwner)
    }
}

/// «Координация» — одно место работы по задаче (владелец 12.11.2026: «давай
/// сольём вместе»). Раньше было два экрана: «Координация» для командного плана
/// и Mission Control для плана оркестратора. Теперь вкладки:
/// «Ход» — сессии исполнителей; «План» — прежняя координация с правкой плана;
/// «Лента» — лента активности карточки, она же переписка по задаче; «Миссия» —
/// контракт, журнал и навыки, видна только когда у задачи есть контракт.
struct MissionControlScreen: View {
    /// Задача плана (у карточки-ветки это родитель с общим планом).
    let taskID: String
    /// Карточка, чья лента показывается во вкладке «Лента».
    var feed: TaskFormViewModel? = nil
    var allowsPlanChanges = true
    /// С какой вкладки открыть (из карточки — сразу «Лента»).
    var initialTab: Tab? = nil

    enum Tab: String, CaseIterable, Identifiable {
        case run = "Ход"
        case plan = "План"
        case feed = "Лента"
        case mission = "Миссия"
        var id: String { rawValue }
    }

    @State private var model = MissionControlModel()
    @State private var tab: Tab?
    /// Данные вкладки «План» — та же модель, что у прежней «Координации».
    @StateObject private var coordination = CoordinationState()
    @State private var selectedSlot: String?
    @State private var stageSlot: String?
    @State private var draft = ""
    @State private var sending = false
    @State private var sendError: String?
    @State private var isPromptExpanded = false
    @State private var showPauseConfirm = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SessionStore.self) private var session

    private var isOwner: Bool { session.currentUser?.role == .owner }
    private var board: CoordinationBoardModel { model.board }
    private var stages: [CoordinationStage] { board.orderedStages }
    private var paused: Bool { board.plan?.pausedAt != nil }

    private var slots: [MissionProgress.Slot] {
        stages.map {
            MissionProgress.Slot(key: $0.id, roleKey: $0.node.roleKey, isDone: $0.isDone, isActive: $0.isActive,
                                 needsOwner: $0.needsOwner, isSkipped: $0.isSkipped)
        }
    }

    private var hasContract: Bool { !model.assertions.isEmpty || model.outcome != nil }

    /// Вкладки по наличию данных: без плана нет «Хода» и «Плана», без
    /// контракта — «Миссии»; «Лента» есть всегда, когда открыта из карточки.
    private var tabs: [Tab] {
        var result: [Tab] = []
        if board.plan != nil { result += [.run, .plan] }
        if feed != nil { result.append(.feed) }
        if hasContract { result.append(.mission) }
        return result.isEmpty ? [feed != nil ? .feed : .run] : result
    }

    private var currentTab: Tab {
        let wanted = tab ?? initialTab ?? (board.plan != nil ? .run : .feed)
        return tabs.contains(wanted) ? wanted : tabs[0]
    }

    private var currentStage: CoordinationStage? {
        let sessions = MissionProgress.sessions(slots: slots)
        if let selectedSlot, sessions.contains(selectedSlot) { return board.stage(selectedSlot) }
        return MissionProgress.defaultSession(slots: slots).flatMap { board.stage($0) }
    }

    var body: some View {
        content
            .coordinationTabBar {
                if tabs.count > 1 { tabPicker }
            }
            .tfScreenBackground()
            .tfNativeHeader("Координация", displayMode: .inline)
            .hintAnchor(HintAnchorID.missionControlScreen)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                if currentTab == .run, isOwner, let stage = currentStage, stage.subtask != nil { composer(stage) }
            }
        .refreshable { await model.load(taskID: taskID, isOwner: isOwner) }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await model.load(taskID: taskID, isOwner: isOwner)
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
        .tfSheet(isPresented: Binding(get: { stageSlot != nil }, set: { if !$0 { stageSlot = nil } })) {
            if let stageSlot {
                CoordinationStageSheet(taskID: taskID, slot: stageSlot, model: board, editable: false)
            }
        }
        .confirmationDialog("Поставить миссию на паузу?", isPresented: $showPauseConfirm, titleVisibility: .visible) {
            Button("На паузу", role: .destructive) {
                Task { await model.setPaused(true, taskID: taskID, isOwner: isOwner) }
            }
        } message: {
            Text("Идущие этапы будут прерваны, новые не стартуют. Сделанное сохранится.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch currentTab {
        case .plan:
            CoordinationScreen(state: coordination, taskId: taskID, allowsPlanChanges: allowsPlanChanges,
                               onOpenTaskControls: { dismiss() })
        case .feed:
            if let feed {
                List {
                    TaskActivityFeed(viewModel: feed)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        case .run, .mission:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: TFSpacing.lg) {
                    header
                    if currentTab == .run { runTab } else { missionTab }
                }
                .padding(.top, TFSpacing.sm)
                .padding(.bottom, TFSpacing.lg)
            }
        }
    }

    // MARK: - Шапка

    private var header: some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                Text("Миссия").tfText(.caption).foregroundStyle(Color.tfDim)
                Text(model.executors?.taskTitle ?? "Загружаем…")
                    .tfText(.title)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(2)
            }
            HStack(alignment: .top, spacing: TFSpacing.lg) {
                metric("Время") { timeText }
                metric("Прогресс") {
                    let progress = MissionProgress.progress(slots: slots)
                    Text("\(progress.done)/\(progress.total)")
                }
                metric("Расход") { Text(MissionProgress.tokens(model.executors?.time?.tokens ?? 0)) }
            }
            statusBar
            if let error = model.error {
                TFErrorBanner(error, variant: .block).accessibilityIdentifier("mission.error")
            }
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    private func metric<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).tfText(.caption).foregroundStyle(Color.tfDim)
            value().tfText(.title).foregroundStyle(Color.tfText).monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Секунды тикают на месте, только пока работа идёт: сервер опрашивается реже.
    @ViewBuilder
    private var timeText: some View {
        let seconds = model.executors?.time?.workedSeconds ?? 0
        if model.executors?.time?.running == true, !paused {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(MissionProgress.duration(seconds: seconds + Int(context.date.timeIntervalSince(model.timeFetchedAt))))
            }
        } else {
            Text(MissionProgress.duration(seconds: seconds))
        }
    }

    private var statusBar: some View {
        HStack(spacing: TFSpacing.md) {
            Text(MissionProgress.status(slots: slots, paused: paused))
                .tfText(.meta)
                .foregroundStyle(paused ? Color.tfOrange : Color.tfSub)
                .lineLimit(1)
                .accessibilityIdentifier("mission.status")
            progressBar
            if isOwner, board.ownsStructure, MissionProgress.canPause(slots: slots, paused: paused) {
                TFIconButton(paused ? "play.fill" : "pause.fill", label: paused ? "Продолжить миссию" : "Поставить на паузу") {
                    if paused {
                        Task { await model.setPaused(false, taskID: taskID, isOwner: isOwner) }
                    } else {
                        showPauseConfirm = true
                    }
                }
                .accessibilityIdentifier("mission.pause")
            }
        }
    }

    private var progressBar: some View {
        let progress = MissionProgress.progress(slots: slots)
        let share = progress.total > 0 ? CGFloat(progress.done) / CGFloat(progress.total) : 0
        return Capsule()
            .fill(Color.tfCard2)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(Color.tfSub).frame(width: proxy.size.width * share)
                }
            }
            .frame(height: 4)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var tabPicker: some View {
        Picker("Раздел", selection: Binding(get: { currentTab }, set: { tab = $0 })) {
            ForEach(tabs) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.vertical, TFSpacing.xs)
        .accessibilityIdentifier("mission.tabs")
    }

    // MARK: - Ход

    @ViewBuilder
    private var runTab: some View {
        if model.loading && !model.loaded {
            TFLoading(.inline).frame(maxWidth: .infinity)
        } else if stages.isEmpty {
            TFEmptyState(icon: "person.2", text: "Команды пока нет", description: "Сессии появятся, когда план будет утверждён.")
        } else {
            sessionStrip
            if let stage = currentStage {
                sessionBody(stage)
            }
        }
    }

    /// Сессии: оркестратор и его команда. На настольном образце это левая колонка.
    private var sessionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TFSpacing.sm) {
                ForEach(MissionProgress.sessions(slots: slots), id: \.self) { slot in
                    if let stage = board.stage(slot) { sessionChip(stage) }
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
        }
    }

    private func sessionChip(_ stage: CoordinationStage) -> some View {
        let isSelected = currentStage?.id == stage.id
        return Button {
            selectedSlot = stage.id
            isPromptExpanded = false
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(board.roleTitle(stage.node.roleKey)).tfText(.meta).foregroundStyle(Color.tfText).lineLimit(1)
                Text(stage.label).tfText(.caption).foregroundStyle(stage.tint).lineLimit(1)
            }
            .padding(.horizontal, TFSpacing.md)
            .padding(.vertical, TFSpacing.sm)
            .background(Color.tfCard, in: RoundedRectangle(cornerRadius: TFRadius.lg, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: TFRadius.lg, style: .continuous).strokeBorder(Color.tfSub, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("mission.session.\(stage.id)")
    }

    private func sessionBody(_ stage: CoordinationStage) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            promptCard(stage)
            if let subtask = stage.subtask {
                TaskLiveActivityView(taskID: stage.node.taskId ?? taskID, subtaskID: subtask.id)
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                    .id(subtask.id)
            } else {
                Text("Этап ещё не начат.").tfText(.body).foregroundStyle(Color.tfSub)
            }
            TFActionRow(title: "Открыть этап", icon: "rectangle.portrait.and.arrow.right") { stageSlot = stage.id }
                .accessibilityIdentifier("mission.open-stage")
            if let sendError { TFErrorBanner(sendError, variant: .block) }
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    /// Задание сессии сверху хода, как закреплённый промпт на образце.
    private func promptCard(_ stage: CoordinationStage) -> some View {
        let text = stage.node.instructions?.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = (text?.isEmpty == false ? text : nil) ?? stage.node.expectedResult
        return Button { isPromptExpanded.toggle() } label: {
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                Text("Задание").tfText(.caption).foregroundStyle(Color.tfDim)
                Text(prompt)
                    .tfText(.action)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(isPromptExpanded ? nil : 2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(TFSpacing.md)
            .background(Color.tfCard, in: RoundedRectangle(cornerRadius: TFRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mission.prompt")
    }

    private func composer(_ stage: CoordinationStage) -> some View {
        HStack(spacing: TFSpacing.sm) {
            TFTextField("Написать: \(board.roleTitle(stage.node.roleKey))", text: $draft)
                .accessibilityIdentifier("mission.composer")
            TFIconButton("paperplane.fill", label: "Отправить") { send(to: stage) }
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.vertical, TFSpacing.sm)
        .tfScreenBackground()
    }

    private func send(to stage: CoordinationStage) {
        guard let subtask = stage.subtask else { return }
        let text = draft
        draft = ""
        sending = true
        Task {
            let sender = ExecutorWindowModel()
            await sender.send(taskID: stage.node.taskId ?? taskID, subtaskID: subtask.id, text: text, executorID: subtask.agentId)
            sendError = sender.error
            if sender.error != nil { draft = text }
            sending = false
        }
    }

    // MARK: - Миссия

    @ViewBuilder
    private var missionTab: some View {
        VStack(alignment: .leading, spacing: TFSpacing.xl) {
            modelsSection
            worksSection
            contractSection
            if !model.skills.isEmpty { skillsSection }
            if isOwner, let context = board.context { TaskContextSection(context: context, roleTitle: board.roleTitle(_:)) }
            logSection
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    private func block<Content: View>(_ title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                TFPlainSectionTitle(title)
                Spacer(minLength: 0)
                if let trailing { Text(trailing).tfText(.meta).foregroundStyle(Color.tfSub).monospacedDigit() }
            }
            content()
        }
    }

    /// На какой модели фактически работала каждая роль: последняя известная по журналу.
    private var modelsSection: some View {
        block("Модели") {
            let rows = roleModels
            if rows.isEmpty {
                Text("Роли ещё не запускались").tfText(.action).foregroundStyle(Color.tfSub)
            }
            ForEach(rows, id: \.role) { row in
                TFInfoRow(label: row.role, value: row.model)
            }
        }
    }

    private var roleModels: [(role: String, model: String)] {
        var seen = Set<String>()
        var rows: [(role: String, model: String)] = []
        for stage in stages where seen.insert(stage.node.roleKey).inserted {
            let model = stages
                .filter { $0.node.roleKey == stage.node.roleKey }
                .compactMap { self.model.activity?.forSubtask($0.subtask?.id).stats?.model }
                .last
            rows.append((board.roleTitle(stage.node.roleKey), model ?? "Ещё не работала"))
        }
        return rows
    }

    private var worksSection: some View {
        let team = stages.filter { !$0.isSkipped && !["code_orchestrator", "orchestrator"].contains($0.node.roleKey) }
        return block("Работы", trailing: "\(team.filter(\.isDone).count)/\(team.count)") {
            if team.isEmpty {
                Text("Оркестратор ещё не разложил работу").tfText(.action).foregroundStyle(Color.tfSub)
            }
            ForEach(team) { stage in
                Button { stageSlot = stage.id } label: {
                    VStack(alignment: .leading, spacing: TFSpacing.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                            Text(board.roleTitle(stage.node.roleKey)).tfText(.body).foregroundStyle(Color.tfText)
                            Spacer(minLength: 0)
                            Text(stage.label).tfText(.caption).foregroundStyle(stage.tint)
                        }
                        Text(stage.node.expectedResult)
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(TFTapRowStyle())
                .accessibilityIdentifier("mission.work.\(stage.id)")
            }
        }
    }

    @ViewBuilder
    private var contractSection: some View {
        if model.unsupported {
            block("Контракт") {
                Text("Сервер пока не знает про контракт миссий").tfText(.body).foregroundStyle(Color.tfText)
                    .accessibilityIdentifier("mission.unsupported")
                Text("Обновите TaskFlow на .110, и экран покажет контракт задачи.").tfText(.action).foregroundStyle(Color.tfSub)
            }
        } else if let outcome = model.outcome, outcome.hasContract {
            block("Контракт", trailing: "\(outcome.passed)/\(outcome.total)") {
                if outcome.failed > 0 { TFInfoRow(label: "Не пройдено", value: "\(outcome.failed)", valueColor: .tfRed) }
                if outcome.blocked > 0 { TFInfoRow(label: "Не проверяется вживую", value: "\(outcome.blocked)", valueColor: .tfOrange) }
                if outcome.pending > 0 { TFInfoRow(label: "Ещё не проверено", value: "\(outcome.pending)") }
                TFInfoRow(label: "Миссия", value: outcome.closed ? "закрыта" : "открыта", valueColor: outcome.closed ? .tfGreen : .tfText)
                ForEach(model.assertions) { assertion in assertionRow(assertion) }
                ForEach(model.coverage?.violations ?? [], id: \.message) { violation in
                    Text(violation.message).tfText(.action).foregroundStyle(Color.tfRed)
                }
            }
        } else if model.loaded {
            block("Контракт") {
                Text("Контракт не записан").tfText(.body).foregroundStyle(Color.tfText)
                    .accessibilityIdentifier("mission.no-contract")
                Text("Оркестратор записывает его до разбиения работы: что считается готовым. Так критерии не подгоняются под получившееся.")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
            }
        }
    }

    private func assertionRow(_ assertion: MissionAssertion) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                Text(assertion.title).tfText(.body).foregroundStyle(Color.tfText)
                Spacer(minLength: 0)
                Text(assertion.statusEnum.title).tfText(.caption).foregroundStyle(color(for: assertion.statusEnum))
            }
            Text(assertion.behavior).tfText(.action).foregroundStyle(Color.tfSub)
            if let slot = assertion.claimedBySlot {
                Text("Закрыл этап: \(board.stage(slot).map { board.roleTitle($0.node.roleKey) } ?? slot)")
                    .tfText(.caption)
                    .foregroundStyle(Color.tfDim)
            }
        }
        .padding(.top, TFSpacing.xs)
    }

    private var skillsSection: some View {
        block("Навыки миссии") {
            ForEach(model.skills) { skill in
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    Text(skill.name).tfText(.body).foregroundStyle(Color.tfText)
                    Text(skill.description).tfText(.action).foregroundStyle(Color.tfSub)
                    Text("Роль: \(skill.role)").tfText(.caption).foregroundStyle(Color.tfDim)
                }
            }
        }
    }

    private var logSection: some View {
        block("Журнал") {
            if model.events.isEmpty {
                Text("Событий пока нет").tfText(.action).foregroundStyle(Color.tfSub)
            }
            ForEach(model.events.prefix(40)) { event in
                HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                    Text(String(event.ts.replacingOccurrences(of: "T", with: " ").prefix(16).dropFirst(5)))
                        .tfText(.caption)
                        .foregroundStyle(Color.tfDim)
                        .monospacedDigit()
                    Text(event.kindTitle).tfText(.action).foregroundStyle(Color.tfText)
                    Spacer(minLength: 0)
                }
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

private extension View {
    /// Переключатель вкладок над прокруткой. На iOS 26 — `safeAreaBar`: под ним
    /// система сама размывает уходящий текст, как под шапкой. Раньше — вставка
    /// с фоном экрана, иначе текст ленты просвечивал сквозь вкладки.
    @ViewBuilder
    func coordinationTabBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .top) { bar() }
        } else {
            safeAreaInset(edge: .top, spacing: 0) { bar().tfScreenBackground() }
        }
    }
}
