import SwiftUI

/// Панель этапа: что сделано или ожидается, что приходит на этап, и всё, что
/// владелец может с ним сделать. Начатый этап не меняется: ему можно только
/// написать.
struct CoordinationStageSheet: View {
    let taskID: String
    let slot: String
    let model: CoordinationBoardModel
    /// Менять план. В Mission Control панель только для чтения.
    let editable: Bool
    var resolution: APIClient.CoordinationResolution? = nil
    var compatible = true
    var onOpenTaskControls: () -> Void = {}
    var onChanged: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var inner: Inner?
    @State private var showRemove = false
    @State private var showSkip = false
    @State private var skipReason = ""
    @State private var showRestart = false
    @State private var restartReason = ""
    @State private var restarting = false
    @State private var actionError: String?
    @State private var showDetails = false

    private enum Inner: Identifiable {
        case talk(String)
        case append
        case split
        case edit
        var id: String {
            switch self {
            case .talk: "talk"
            case .append: "append"
            case .split: "split"
            case .edit: "edit"
            }
        }
    }

    private var isOwner: Bool { session.currentUser?.role == .owner }
    private var stage: CoordinationStage? { model.stage(slot) }
    private var canChange: Bool { editable && isOwner && model.ownsStructure }

    var body: some View {
        NavigationStack {
            List {
                if let stage, let plan = model.plan {
                    stateSection(stage)
                    workSections(stage)
                    incomingSection(stage, plan: plan)
                    contextSection(stage)
                    problemSection
                    actionsSection(stage)
                }
                if let actionError {
                    Section { TFErrorBanner(actionError, variant: .block) }
                }
            }
            .listStyle(.plain)
            .tfScreenBackground()
            .navigationTitle(stage.map { model.roleTitle($0.node.roleKey) } ?? "Этап")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
            .navigationDestination(for: AppRoute.self) { routeDestination($0) }
            .tfSheet(item: $inner) { innerSheet($0) }
            .tfSheet(isPresented: $showDetails) { ResolutionDetailsSheet(resolution: resolution) }
            .confirmationDialog("Убрать этап?", isPresented: $showRemove, titleVisibility: .visible) {
                Button("Убрать", role: .destructive) { remove() }
            } message: {
                Text("Те, кто ждал этот этап, будут ждать его предшественников.")
            }
            .alert("Почему пропускаем?", isPresented: $showSkip) {
                TextField("Причина", text: $skipReason)
                Button("Пропустить") { skip() }
                    .disabled(skipReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Пропуск виден в плане отдельно от сдачи — причина нужна, чтобы потом было понятно, почему шаг не делали.")
            }
            .alert("Перезапустить этап?", isPresented: $showRestart) {
                TextField("Причина перезапуска", text: $restartReason)
                Button("Перезапустить", role: .destructive) { restart() }
                    .disabled(restartReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || restartReason.count > 1000)
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Текущая попытка будет остановлена, затем запущена новая. Другие этапы не перезапускаются.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Разделы

    private func stateSection(_ stage: CoordinationStage) -> some View {
        Section {
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                Text(stage.label).tfText(.meta).foregroundStyle(stage.tint)
                if let reason = stage.node.skipReason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
                    Text(reason).tfText(.action).foregroundStyle(Color.tfSub)
                }
                ForEach(stage.node.waitingFor ?? [], id: \.fromSlotKey) { waiting in
                    Text("Ждёт: \(authorTitle(waiting.fromSlotKey)), \(waiting.reason)")
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                }
            }
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private func workSections(_ stage: CoordinationStage) -> some View {
        if let result = stage.result {
            TFPlainSection(stage.isDone ? "Итог" : "Прошлый результат") {
                TaskRoleReply(text: result)
                    .textSelection(.enabled)
                    .listRowSeparator(.hidden)
                if let document = stage.node.resultDocument {
                    NavigationLink {
                        NoteEditorScreen(noteID: document.id)
                    } label: {
                        Text("Отчёт о работе").tfText(.body).foregroundStyle(Color.tfText)
                    }
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("coord.stage.report")
                }
            }
        }
        if !stage.isDone {
            TFPlainSection("Ожидаемый результат") {
                Text(stage.node.expectedResult)
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                    .textSelection(.enabled)
                    .listRowSeparator(.hidden)
            }
        }
        if let task = stage.node.instructions?.trimmingCharacters(in: .whitespacesAndNewlines), !task.isEmpty {
            TFPlainSection("Задание") {
                Text(task)
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                    .textSelection(.enabled)
                    .listRowSeparator(.hidden)
            }
        }
    }

    /// Что приходит на этап: итоги тех, кого он ждёт.
    @ViewBuilder
    private func incomingSection(_ stage: CoordinationStage, plan: ApiCollaborationPlan) -> some View {
        let sources = plan.edges.filter { $0.toSlotKey == stage.id }.compactMap { model.stage($0.fromSlotKey) }
        if !sources.isEmpty {
            TFPlainSection("Что приходит на этап") {
                ForEach(sources) { source in
                    VStack(alignment: .leading, spacing: TFSpacing.xs) {
                        Text(model.roleTitle(source.node.roleKey)).tfText(.body).foregroundStyle(Color.tfText)
                        Text(source.result ?? "Ещё не сдано. \(source.label)")
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                            .lineLimit(4)
                    }
                    .listRowSeparator(.hidden)
                }
            }
        }
    }

    /// Какие источники контекста сработали на этом этапе, а какие нет.
    @ViewBuilder
    private func contextSection(_ stage: CoordinationStage) -> some View {
        if isOwner, let subtask = stage.subtask, let sources = model.context?.stages[subtask.id], !sources.isEmpty {
            TFPlainSection("Контекст этапа") {
                ForEach(sources) { source in
                    StageContextRow(source: source).listRowSeparator(.hidden)
                }
            }
        }
    }

    /// Причина из разбора сервера и его действие: всё, что раньше было под графом.
    @ViewBuilder
    private var problemSection: some View {
        if let r = resolution {
            TFPlainSection("Почему в этом состоянии") {
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    Text(r.displayStatus).tfText(.body).foregroundStyle(Color.tfText)
                    TFInfoRow(label: "Ответственный", value: r.assigneeName ?? "Не указан сервером")
                    if let notes = r.notes, !notes.isEmpty {
                        Text(notes).tfText(.action).foregroundStyle(Color.tfSub).textSelection(.enabled)
                    }
                    if let waiting = r.waitingFor, !waiting.isEmpty {
                        Text("Ожидает: " + waiting.joined(separator: ", ")).tfText(.action).foregroundStyle(Color.tfSub)
                    }
                }
                .listRowSeparator(.hidden)
                if r.actionEnum == .switchProvider || r.actionEnum == .fixConfig {
                    NavigationLink(value: AppRoute.runtimeProviders) {
                        Text("Открыть настройки моделей").tfText(.body).foregroundStyle(Color.tfText)
                    }
                    .disabled(!compatible || restarting)
                    .listRowSeparator(.hidden)
                } else {
                    ActionBar(resolution: r, blockedByVersionMismatch: !compatible, enabled: !restarting) { _ in
                        if r.canRestartStep {
                            restartReason = ""
                            showRestart = true
                        } else {
                            onOpenTaskControls()
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }
                TFActionRow(title: "Подробности состояния", icon: "info.circle") { showDetails = true }
                    .listRowSeparator(.hidden)
            }
        }
    }

    @ViewBuilder
    private func actionsSection(_ stage: CoordinationStage) -> some View {
        TFPlainSection("Действия") {
            if let subtask = stage.subtask {
                TFActionRow(title: "Поговорить с ролью", icon: "bubble.left.and.bubble.right") {
                    inner = .talk(subtask.id)
                }
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("coord.stage.talk")
            }
            if !stage.isDone, !stage.isSkipped, isOwner, editable || !stage.isPending {
                TFActionRow(title: "Дописать задачу", icon: "text.badge.plus") { inner = .append }
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("coord.stage.append")
            }
            if canChange, !stage.isDone, !stage.isSkipped, let plan = model.plan, CoordinationBoard.canGrow(plan) {
                TFActionRow(title: "Распараллелить", icon: "arrow.triangle.branch") { inner = .split }
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("coord.stage.split")
            }
            if canChange, stage.isPending {
                TFActionRow(title: "Изменить этап и порядок", icon: "pencil") { inner = .edit }
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("coord.stage.edit")
                TFActionRow(title: "Пропустить", icon: "forward") {
                    skipReason = ""
                    showSkip = true
                }
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("coord.stage.skip")
                TFActionRow(title: "Убрать", icon: "trash", color: .tfRed) { showRemove = true }
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("coord.stage.remove")
            }
        }
    }

    // MARK: - Внутренние шторки

    @ViewBuilder
    private func innerSheet(_ sheet: Inner) -> some View {
        switch sheet {
        case .talk(let subtaskID):
            ExecutorWindow(taskID: stage?.node.taskId ?? taskID, subtaskID: subtaskID)
        case .append:
            if let stage {
                CoordinationAppendSheet(stage: stage) { text in append(text, to: stage) }
            }
        case .split:
            if let stage, let plan = model.plan {
                editor(.add, plan: plan, preset: CoordinationBoard.split(stage.node, in: plan, pending: model.pendingSlots))
            }
        case .edit:
            if let stage, let plan = model.plan {
                editor(.edit(stage.node), plan: plan, preset: nil)
            }
        }
    }

    private func editor(_ mode: PlanStepEditorSheet.Mode, plan: ApiCollaborationPlan,
                        preset: CoordinationBoard.StepPreset?) -> some View {
        PlanStepEditorSheet(
            mode: mode, plan: plan, roles: model.roleOptions, pendingSlots: model.pendingSlots,
            roleTitle: model.roleTitle(_:),
            onSave: { op in run([op]) },
            preset: preset
        )
    }

    // MARK: - Правки

    private func authorTitle(_ slot: String) -> String {
        model.stage(slot).map { model.roleTitle($0.node.roleKey) } ?? slot
    }

    private func run(_ ops: [ApiPlanOp], thenClose: Bool = false) {
        Task {
            let done = await model.apply(ops, taskID: taskID, isOwner: isOwner)
            if done {
                onChanged()
                if thenClose { dismiss() }
            }
        }
    }

    private func remove() {
        run([ApiPlanOp(op: "remove_step", slotKey: slot)], thenClose: true)
    }

    private func skip() {
        run([ApiPlanOp(op: "skip_step", slotKey: slot, reason: skipReason)])
    }

    /// Неначатому этапу задание дописывается в план, и роль получит его целиком
    /// при старте. Начатый не меняется: дописанное уходит ему сообщением.
    private func append(_ text: String, to stage: CoordinationStage) {
        if stage.isPending, canChange {
            let task = CoordinationBoard.appended(text, to: stage.node.instructions)
            run([ApiPlanOp(op: "update_step", slotKey: stage.id, instructions: task)])
            return
        }
        guard let subtask = stage.subtask else { return }
        Task {
            let sender = ExecutorWindowModel()
            await sender.send(taskID: stage.node.taskId ?? taskID, subtaskID: subtask.id, text: text,
                              executorID: subtask.agentId)
            actionError = sender.error
            onChanged()
        }
    }

    private func restart() {
        guard let target = resolution, !restarting else { return }
        restarting = true
        Task {
            defer { restarting = false }
            do {
                try await APIClient().restartCoordinationStep(target, reason: restartReason)
                actionError = nil
            } catch {
                actionError = error.localizedDescription
            }
            onChanged()
        }
    }
}

/// Дописать задачу этапу. Текст объясняет, куда он уйдёт: в задание или сообщением.
private struct CoordinationAppendSheet: View {
    let stage: CoordinationStage
    let onSend: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Что добавить", text: $text, axis: .vertical)
                        .tfText(.input)
                        .lineLimit(3...10)
                        .accessibilityIdentifier("coord.append.text")
                        .listRowSeparator(.hidden)
                    Text(stage.isPending
                         ? "Допишется в задание этапа. Роль получит его целиком, когда до неё дойдёт ход."
                         : "Этап уже начат, поэтому текст уйдёт роли сообщением.")
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .tfScreenBackground()
            .navigationTitle("Дописать задачу")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Отправить") {
                        onSend(text)
                        dismiss()
                    }
                    .disabled(isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
