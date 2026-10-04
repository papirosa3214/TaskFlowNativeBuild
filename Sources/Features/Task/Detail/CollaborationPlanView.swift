import SwiftUI

/// Краткий граф совместной работы над задачей — LOCK-246, этап 10 плана
/// docs/2026-09-28-parent-child-execution-context.
///
/// Чистый SwiftUI без своих tint/background/overlay/рамок: строка живёт
/// внутри системного `Section` в `TaskFormScreen`, фон рисует список сам.
/// Рисует, только если у задачи есть УТВЕРЖДЁННЫЙ план — черновики ещё
/// ничего не запускают и путали бы владельца. У большинства задач approved
/// плана нет вовсе: тогда `body` — `EmptyView()`, как и у соседних
/// `AttemptLadderView`/`AgentOwnerActions`.
///
/// Runtime-состояние узлов — с 29.09.2026 обычные подзадачи
/// (`collaborationPlanId`/`planNodeKey`), не отдельная сущность
/// (docs/2026-09-29-role-slot-execution-integration/DESIGN.md, владелец:
/// «роли плана — это подзадачи»). У subtasks нет отдельного персистентного
/// состояния «готов к старту» (сервер стартует узел сам, как только это
/// становится верным) — «ready» здесь вычисляется на клиенте из entries
/// и edges: waiting-узел, у которого все предшественники уже done.
public struct CollaborationPlanView: View {
    let taskId: String
    /// Подзадачи карточки — она обновляет их опросом. Состояния узлов берём
    /// отсюда: своя загрузка ниже идёт один раз, и граф замирал в том виде,
    /// в каком был при открытии (владелец 01.10.2026, T05: «исследователь в
    /// работе» всю дорогу, хотя пятеро уже сдали).
    var subtasks: [ApiSubtask] = []
    var allowsPlanChanges = true
    /// Родитель прячет весь `Section` целиком, пока плана нет — иначе на
    /// 99% карточек без плана оставалась бы пустая секция с системными
    /// отступами. Обновляется по факту загрузки, не заранее.
    @Binding var hasApprovedPlan: Bool

    private let state: CollaborationPlanState
    private let reloadToken: Int
    private var plan: ApiCollaborationPlan? { state.plan }
    /// Черновик, ещё не утверждённый — LOCK-249. Показывается владельцу
    /// вместе с той же графовой раскладкой, что и approved — чтобы было
    /// видно, что именно утверждаешь. Сама кнопка «Утвердить» живёт не
    /// здесь, а в меню «Ещё» карточки (владелец: там уже все действия над
    /// задачей, отдельная кнопка в теле карточки — лишняя); `id` черновика
    /// пробрасывается наружу через `pendingApprovalPlanId`, родитель зовёт
    /// API и форсирует перезагрузку этой вьюхи через `.id(...)`.
    private var draftPlan: ApiCollaborationPlan? { state.draftPlan }
    private var planSubtasks: [ApiSubtask] { state.subtasks }
    private var roleTitles: [String: String] { state.roleTitles }
    private var roleOptions: [PlanRoleOption] { state.roleTitles.keys.sorted().map { PlanRoleOption(key: $0, title: graphTitle(for: $0)) } }
    /// Живой план (01.10.2026): открытый лист шага / редактора.
    @State private var sheet: PlanSheet?
    @State private var detailSubtasks: [String: [ApiSubtask]] = [:]
    @State private var isApplying = false
    @State private var errorMessage: String?

    private enum PlanSheet: Identifiable {
        case detail(planID: String, slot: String)
        case add(planID: String)
        case edit(planID: String, slot: String)

        var id: String {
            switch self {
            case .detail(let plan, let slot): "detail-\(plan)-\(slot)"
            case .add(let plan): "add-\(plan)"
            case .edit(let plan, let slot): "edit-\(plan)-\(slot)"
            }
        }
    }

    @Binding var pendingApprovalPlanId: String?
    @Binding var pendingBranchSnapshot: String?

    @Environment(SessionStore.self) private var session
    private var isOwner: Bool { session.currentUser?.role == .owner }

    private let api = APIClient()

    public init(taskId: String, state: CollaborationPlanState? = nil, reloadToken: Int = 0, subtasks: [ApiSubtask] = [], allowsPlanChanges: Bool = true, hasApprovedPlan: Binding<Bool>, pendingApprovalPlanId: Binding<String?>, pendingBranchSnapshot: Binding<String?> = .constant(nil)) {
        self.taskId = taskId
        self.state = state ?? CollaborationPlanState()
        self.reloadToken = reloadToken
        self.subtasks = subtasks
        self.allowsPlanChanges = allowsPlanChanges
        self._hasApprovedPlan = hasApprovedPlan
        self._pendingApprovalPlanId = pendingApprovalPlanId
        self._pendingBranchSnapshot = pendingBranchSnapshot
    }


    public var body: some View {
        // Пока plan == nil, тело ниже пустое — List не шлёт onAppear
        // пустой ячейке вовсе (проверено на устройстве 28.09.2026). Якорь
        // нулевого размера всегда присутствует в дереве, поэтому lifecycle
        // гарантированно срабатывает.
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(width: 0, height: 0)
            if let draftPlan, isOwner {
                draftSection(draftPlan)
            }
            if let plan {
                content(for: plan)
            }
        }
        .task(id: taskId) {
            await load(force: false)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard !isApplying else { continue }
                await load()
            }
        }
        .onChange(of: subtasks.map { "\($0.id):\($0.done):\($0.agentState?.rawValue ?? "")" }.joined(separator: "|")) { _, _ in
            Task { await load() }
        }
        .sheet(item: $sheet) { sheet in
            sheetView(sheet)
        }
        .alert("План не изменён", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Живой план: листы и правки

    @ViewBuilder
    private func sheetView(_ sheet: PlanSheet) -> some View {
        switch sheet {
        case .detail(let planID, let slot):
            if let plan = planWith(planID), let node = plan.nodes.first(where: { $0.slotKey == slot }) {
                let subtask = subtaskFor(plan: plan, slot: slot)
                PlanStepDetailSheet(
                    node: node,
                    assignments: plan.branchTeam == nil ? [] : plan.nodes.filter { $0.roleKey == node.roleKey && !$0.isSkipped },
                    onSelectAssignment: { self.sheet = .detail(planID: planID, slot: $0) },
                    plan: plan,
                    subtask: subtask,
                    roleTitle: graphTitle(for:),
                    stateLabel: Self.stateLabel(node.isSkipped ? "skipped" : node.executionState ?? baseState(for: subtask, plan: plan)),
                    isEditable: isEditable(node, in: plan),
                    onEdit: { self.sheet = .edit(planID: planID, slot: slot) },
                    onSkip: { reason in
                        self.sheet = nil
                        Task { await apply(ApiPlanOp(op: "skip_step", slotKey: slot, reason: reason), to: plan) }
                    },
                    onRemove: {
                        self.sheet = nil
                        Task { await apply(ApiPlanOp(op: "remove_step", slotKey: slot), to: plan) }
                    }
                )
                .presentationDetents([.medium, .large])
                .task(id: node.slotKey) {
                    if let cardID = node.taskId, let steps = try? await api.subtasks(taskId: cardID) {
                        if detailSubtasks[cardID] != steps { detailSubtasks[cardID] = steps }
                    }
                }
            }
        case .add(let planID):
            if let plan = planWith(planID) {
                editor(.add, plan: plan)
            }
        case .edit(let planID, let slot):
            if let plan = planWith(planID), let node = plan.nodes.first(where: { $0.slotKey == slot }) {
                editor(.edit(node), plan: plan)
            }
        }
    }

    private func editor(_ mode: PlanStepEditorSheet.Mode, plan: ApiCollaborationPlan) -> some View {
        let editorPlan: ApiCollaborationPlan
        if case .edit(let node) = mode, plan.branchSnapshot != nil {
            let local = plan.nodes.filter { $0.sourcePlanId == node.sourcePlanId }
            let keys = Set(local.map(\.slotKey))
            editorPlan = ApiCollaborationPlan(id: plan.id, taskId: plan.taskId, revision: plan.revision,
                status: plan.status, profile: plan.profile, rationale: plan.rationale, nodes: local,
                edges: plan.edges.filter { keys.contains($0.fromSlotKey) && keys.contains($0.toSlotKey) },
                version: plan.version, pendingProposals: plan.pendingProposals,
                branchSnapshot: plan.branchSnapshot, branchRootTaskId: plan.branchRootTaskId)
        } else { editorPlan = plan }
        return PlanStepEditorSheet(
            mode: mode,
            plan: editorPlan,
            roles: roleOptions.isEmpty
                ? Array(Set(plan.nodes.map(\.roleKey))).sorted().map { PlanRoleOption(key: $0, title: graphTitle(for: $0)) }
                : roleOptions,
            pendingSlots: Set(plan.nodes.filter { isEditable($0, in: plan) }.map(\.slotKey)),
            roleTitle: graphTitle(for:),
            onSave: { op in Task { await apply(op, to: plan) } }
        )
    }

    private func planWith(_ id: String) -> ApiCollaborationPlan? {
        if plan?.id == id { return plan }
        if draftPlan?.id == id { return draftPlan }
        return nil
    }

    private func subtaskFor(plan: ApiCollaborationPlan, slot: String) -> ApiSubtask? {
        let node = plan.nodes.first { $0.slotKey == slot }
        let sourcePlan = node?.sourcePlanId ?? plan.id
        let sourceSlot = node?.sourceSlotKey ?? slot
        let source = node?.taskId.flatMap { detailSubtasks[$0] } ?? (subtasks + planSubtasks)
        return source.first { $0.collaborationPlanId == sourcePlan && $0.planNodeKey == sourceSlot }
    }

    /// Менять можно только неначатый шаг и только владельцу: у черновика —
    /// любой, у запущенного — без галочки и без состояния работы.
    private func isEditable(_ node: ApiCollaborationPlanNode, in plan: ApiCollaborationPlan) -> Bool {
        guard isOwner, allowsPlanChanges, !node.isSkipped else { return false }
        if plan.branchSnapshot != nil {
            return plan.status == "draft" && node.sourcePlanStatus == "draft"
        }
        if plan.status != "approved" { return true }
        guard let subtask = subtaskFor(plan: plan, slot: node.slotKey) else { return true }
        return !subtask.done && subtask.agentState == nil
    }

    private func canAddSteps(to plan: ApiCollaborationPlan) -> Bool {
        guard plan.branchSnapshot == nil, isOwner, allowsPlanChanges else { return false }
        if plan.status != "approved" { return true }
        return false
    }

    private func apply(_ op: ApiPlanOp, to plan: ApiCollaborationPlan) async {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            let updated = try await api.applyCollaborationPlanOps(taskId: taskId, planId: plan.id,
                                                                  baseVersion: plan.version, ops: [op], branchSnapshot: plan.branchSnapshot)
            replace(updated)
            await reloadSubtasks()
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }

    private func decide(_ proposal: ApiPlanProposal, approve: Bool, in plan: ApiCollaborationPlan) async {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            let updated = try await api.decideCollaborationPlanProposal(taskId: taskId, planId: plan.id,
                                                                        proposalId: proposal.id, approve: approve)
            replace(updated)
            await reloadSubtasks()
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }

    private func replace(_ updated: ApiCollaborationPlan) {
        withAnimation(.snappy(duration: 0.25)) {
            state.replace(updated)
            if draftPlan?.id == updated.id { pendingBranchSnapshot = updated.branchSnapshot }
        }
    }

    private func reloadSubtasks() async {
        if let fresh = try? await api.subtasks(taskId: taskId) {
            let steps = fresh.filter { $0.collaborationPlanId != nil }
            if state.subtasks != steps { state.subtasks = steps }
        }
    }

    // MARK: - Предложения ролей и «Добавить шаг»

    @ViewBuilder
    private func ownerControls(for plan: ApiCollaborationPlan) -> some View {
        if isOwner {
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                ForEach(plan.pendingProposals ?? []) { proposal in
                    proposalCard(proposal, plan: plan)
                }
                if canAddSteps(to: plan) {
                    Button {
                        sheet = .add(planID: plan.id)
                    } label: {
                        Label("Добавить шаг", systemImage: "plus.circle")
                            .tfText(.action)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.tfDim)
                    .disabled(isApplying)
                    .accessibilityIdentifier("plan-add-step")
                }
            }
            .padding(.top, TFSpacing.xs)
        }
    }

    private func proposalCard(_ proposal: ApiPlanProposal, plan: ApiCollaborationPlan) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Text("\(proposal.actorName ?? "Роль") предлагает изменить план")
                .tfText(.action)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tfText)
            ForEach(Array(proposal.ops.enumerated()), id: \.offset) { _, op in
                Text(Self.describe(op, title: graphTitle(for:)))
                    .tfText(.caption)
                    .foregroundStyle(Color.tfSub)
            }
            if let reason = proposal.reason, !reason.isEmpty {
                Text(reason)
                    .tfText(.caption)
                    .foregroundStyle(Color.tfSub)
            }
            HStack(spacing: TFSpacing.md) {
                Button("Одобрить") { Task { await decide(proposal, approve: true, in: plan) } }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.tfGreen)
                Button("Отклонить", role: .destructive) { Task { await decide(proposal, approve: false, in: plan) } }
                    .buttonStyle(.bordered)
            }
            .disabled(isApplying)
            .controlSize(.small)
        }
        .padding(TFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tfOrange.opacity(0.08), in: RoundedRectangle(cornerRadius: TFRadius.lg))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan-proposal")
    }

    static func describe(_ op: ApiPlanOp, title: (String) -> String) -> String {
        switch op.op {
        case "add_step": return "Новый шаг — \(title(op.roleKey ?? "")): \(op.expectedResult ?? "")"
        case "rework": return "Доработка — \(title(op.roleKey ?? "builder")): \(op.defects ?? "")"
        case "skip_step": return "Пропустить шаг: \(op.reason ?? "")"
        case "remove_step": return "Удалить шаг"
        default: return "Изменить шаг"
        }
    }

    /// Черновик целиком: та же раскладка графа, что у approved — владелец
    /// должен видеть роли и порядок ДО утверждения. Кнопка «Утвердить» —
    /// в меню «Ещё» карточки, не здесь.
    @ViewBuilder
    private func draftSection(_ draft: ApiCollaborationPlan) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text("Черновик плана — роли ещё не запущены")
                .tfText(.caption)
                .foregroundStyle(Color.tfOrange)
            content(for: draft)
        }
        .padding(.bottom, TFSpacing.sm)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func content(for plan: ApiCollaborationPlan) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Text(plan.branchSnapshot == nil ? Self.profileLabel(plan.profile) : "Общий план ветки")
                .tfText(.title)
                .fontWeight(.regular)
                .foregroundStyle(Color.tfText)
            CollaborationPlanGraph(
                entries: graphEntries(for: plan),
                edges: graphEdges(for: plan),
                onTap: { slot in
                    let assignments = plan.nodes.filter { $0.roleKey == slot && !$0.isSkipped }
                    let node = assignments.first { $0.executionState == "active" }
                        ?? assignments.first { ["blocked", "returned", "review"].contains($0.executionState ?? "") }
                        ?? assignments.first { $0.executionState != "accepted" }
                        ?? assignments.first
                    sheet = .detail(planID: plan.id, slot: plan.branchTeam == nil ? slot : (node?.slotKey ?? slot))
                }
            )
            ownerControls(for: plan)
        }
        .accessibilityElement(children: .contain)
    }

    /// Базовое состояние узла из его подзадачи — без «ready»: та считается
    /// отдельно в `CollaborationPlanGraph` из entries+edges (нужен полный
    /// список узлов, а не один).
    private func baseState(for subtask: ApiSubtask?, plan: ApiCollaborationPlan) -> String {
        guard plan.status == "approved", let subtask else { return "waiting" }
        if subtask.done { return subtask.result?.hasPrefix("changes_requested:") == true ? "returned" : "accepted" }
        switch subtask.agentState {
        case .inProgress: return "active"
        case .blocked: return "blocked"
        case .review: return "review"
        case .todo, .none: return subtask.state == .running ? "active" : "waiting"
        }
    }

    private func graphEntries(for plan: ApiCollaborationPlan) -> [CollaborationPlanGraph.Entry] {
        if let team = plan.branchTeam {
            return team.map { member in
                .init(slotKey: member.roleKey, roleKey: member.roleKey,
                      title: graphTitle(for: member.roleKey), taskTitle: "team",
                      state: member.executionState, badge: nil,
                      taskNumbers: member.taskNumbers, isParticipant: true)
            }
        }
        return plan.nodes.map { node in
            let subtask = subtaskFor(plan: plan, slot: node.slotKey)
            return .init(
                slotKey: node.slotKey,
                roleKey: node.roleKey,
                title: graphTitle(for: node.roleKey),
                taskTitle: node.taskTitle,
                state: node.isSkipped ? "skipped" : node.executionState ?? baseState(for: subtask, plan: plan),
                badge: node.responsible == true ? "ответственный" : Self.badge(for: node)
            )
        }
    }

    /// Пометка шага, который не из исходного шаблона.
    private static func badge(for node: ApiCollaborationPlanNode) -> String? {
        switch node.origin {
        case "role": return node.roleKey == "critic_verifier" && (node.instructions?.hasPrefix("[taskflow:final-review]") ?? false) ? "присоединился" : "добавлен ролью"
        case "rework": return node.roleKey == "critic_verifier" ? "повторная проверка \(node.iteration ?? 1)" : "доработка \(node.iteration ?? 1)"
        default: return nil
        }
    }

    private func graphEdges(for plan: ApiCollaborationPlan) -> [ApiCollaborationPlanEdge] {
        guard plan.branchTeam != nil else { return plan.edges }
        let roles = Dictionary(uniqueKeysWithValues: plan.nodes.map { ($0.slotKey, $0.roleKey) })
        var seen = Set<String>()
        return plan.edges.compactMap { edge in
            guard let from = roles[edge.fromSlotKey], let to = roles[edge.toSlotKey], from != to,
                  seen.insert("\(from):\(to)").inserted else { return nil }
            return ApiCollaborationPlanEdge(fromSlotKey: from, toSlotKey: to, startCondition: edge.startCondition)
        }
    }

    static func stateLabel(_ state: String) -> String {
        switch state {
        case "returned": "Вернул на доработку"
        case "waiting": "Ждёт"
        case "ready": "Готов к старту"
        case "active": "В работе"
        case "blocked": "Заблокирован"
        case "review": "На проверке"
        case "accepted": "Принято"
        case "skipped": "Пропущен"
        default: state
        }
    }

    private func graphTitle(for roleKey: String) -> String {
        switch roleKey {
        case "designer": "Дизайнер"
        case "critic_verifier": "Критик"
        default: title(for: roleKey)
        }
    }

    private func title(for roleKey: String) -> String {
        roleTitles[roleKey] ?? roleKey
    }

    private func load(force: Bool = true) async {
        await state.load(taskID: taskId, reloadToken: reloadToken, force: force, isOwner: isOwner)
        if hasApprovedPlan != state.isVisible { hasApprovedPlan = state.isVisible }
        let approvalID = isOwner ? draftPlan?.id : nil
        if pendingApprovalPlanId != approvalID { pendingApprovalPlanId = approvalID }
        let snapshot = isOwner ? draftPlan?.branchSnapshot : nil
        if pendingBranchSnapshot != snapshot { pendingBranchSnapshot = snapshot }
    }

    private static func profileLabel(_ profile: String) -> String {
        switch profile {
        case "single_executor": "Один исполнитель"
        case "research": "Исследование"
        case "delivery": "Доставка"
        case "full_cycle": "Полный цикл"
        case "manual": "Вручную"
        case "product_feature": "Продуктовая фича"
        case "bug_regression": "Баг или регрессия"
        default: profile
        }
    }
}

/// Компактная схема зависимостей approved-плана. Подписываем только состояние
/// роли: источник ожидания считывается по входящим линиям, поэтому текст не
/// дублирует сам граф.
private struct CollaborationPlanGraph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    struct Entry: Identifiable {
        let slotKey: String
        let roleKey: String
        let title: String
        var taskTitle: String? = nil
        /// waiting | ready | active | blocked | review | accepted. `ready`
        /// сюда не приходит напрямую (см. `CollaborationPlanView.baseState`)
        /// — считается ниже, в `readyState(for:)`, из entries+edges.
        let state: String
        /// «добавлен ролью», «доработка 1» — шаг не из исходного шаблона.
        var badge: String?
        var taskNumbers: [Int] = []
        var isParticipant = false

        var id: String { slotKey }
    }

    let entries: [Entry]
    let edges: [ApiCollaborationPlanEdge]
    /// Тап по шагу — подробности и правка (живой план, 01.10.2026).
    var onTap: (String) -> Void = { _ in }

    private let nodeHeight: CGFloat = 56
    private let nodeWidth: CGFloat = 56
    private var rowStep: CGFloat { nodeHeight + 20 }

    /// waiting-узел, у которого предшественники (если есть) все уже done
    /// ("accepted") — сервер такой узел стартует сам почти мгновенно,
    /// «ready» здесь наблюдается только в окне до автостарта или если
    /// автостарт сорвался (тогда есть ручной POST /api/subtasks/:id/run —
    /// см. planSubtaskAdmission.ts). Артефактные edges с явным
    /// start_condition="accepted" клиент отличить от «сдано, но не
    /// принято» не может (нет статуса версии артефакта) — упрощение,
    /// сознательно принятое ради того, чтобы не тащить сюда ещё один
    /// запрос ради редкого случая.
    private func readyStates() -> Set<String> {
        if entries.contains(where: { $0.taskTitle != nil }) {
            return Set(entries.filter { $0.state == "ready" }.map(\.slotKey))
        }
        let byKey = Dictionary(uniqueKeysWithValues: entries.map { ($0.slotKey, $0) })
        var ready: Set<String> = []
        for entry in entries where entry.state == "waiting" {
            let incoming = edges.filter { $0.toSlotKey == entry.slotKey }
            let satisfied = incoming.isEmpty || incoming.allSatisfy { ["accepted", "returned"].contains(byKey[$0.fromSlotKey]?.state ?? "") }
            if satisfied { ready.insert(entry.slotKey) }
        }
        return ready
    }

    private func displayState(_ entry: Entry, ready: Set<String>) -> String {
        ready.contains(entry.slotKey) ? "ready" : entry.state
    }

    var body: some View {
        let ready = readyStates()
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            HStack(spacing: TFSpacing.xs) {
                Text("\(ready.count) готов к старту")
                    .tfText(.action)
                    .foregroundStyle(Color.tfGreen)
                Text("•")
                    .tfText(.action)
                    .foregroundStyle(Color.tfDim)
                Text("\(entries.filter { $0.state == "active" }.count) в работе")
                    .tfText(.action)
                    .foregroundStyle(Color.tfOrange)
            }

            GeometryReader { proxy in
                let maxColumns = Dictionary(grouping: entries, by: { levels[$0.slotKey] ?? 0 }).values.map(\.count).max() ?? 1
                let canvasWidth = max(proxy.size.width, CGFloat(maxColumns) * nodeWidth + CGFloat(maxColumns - 1) * TFSpacing.sm)
                let places = layout(width: canvasWidth)
                let centers = places.mapValues { $0.center }

                ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        for edge in edges {
                            guard let fromCenter = centers[edge.fromSlotKey], let toCenter = centers[edge.toSlotKey] else { continue }
                            if entries.contains(where: \.isParticipant) {
                                let path = participantConnection(from: fromCenter, to: toCenter)
                                context.stroke(path, with: .color(ready.contains(edge.fromSlotKey) ? Color.tfGreen.opacity(0.8) : Color.tfDim.opacity(0.75)), lineWidth: 1.2)
                                continue
                            }
                            let horizontal = false
                            let upward = toCenter.y < fromCenter.y
                            let direction: CGFloat = toCenter.x > fromCenter.x ? 1 : -1
                            let from = horizontal
                                ? CGPoint(x: fromCenter.x + direction * nodeWidth / 2, y: fromCenter.y)
                                : CGPoint(x: fromCenter.x, y: fromCenter.y + (upward ? -nodeHeight / 2 : nodeHeight / 2))
                            let to = horizontal
                                ? CGPoint(x: toCenter.x - direction * nodeWidth / 2, y: toCenter.y)
                                : CGPoint(x: toCenter.x, y: toCenter.y + (upward ? nodeHeight / 2 : -nodeHeight / 2))
                            var path = Path()
                            path.move(to: from)
                            if horizontal {
                                path.addLine(to: to)
                            } else if to.y < from.y {
                                // Return links run beside the avatars, not through their faces.
                                let sideX = max(8, min(from.x, to.x) - nodeWidth)
                                path.addLine(to: CGPoint(x: sideX, y: from.y - 8))
                                path.addLine(to: CGPoint(x: sideX, y: to.y + 8))
                                path.addLine(to: CGPoint(x: to.x, y: to.y + 8))
                                path.addLine(to: to)
                            } else {
                                let middleY = (from.y + to.y) / 2
                                path.addLine(to: CGPoint(x: from.x, y: middleY))
                                path.addLine(to: CGPoint(x: to.x, y: middleY))
                                path.addLine(to: to)
                            }
                            if horizontal {
                                path.move(to: CGPoint(x: to.x - direction * 5, y: to.y - 4))
                                path.addLine(to: to)
                                path.addLine(to: CGPoint(x: to.x - direction * 5, y: to.y + 4))
                            } else {
                                path.move(to: CGPoint(x: to.x - 4, y: to.y + (upward ? 5 : -5)))
                                path.addLine(to: to)
                                path.addLine(to: CGPoint(x: to.x + 4, y: to.y + (upward ? 5 : -5)))
                            }
                            let isReadyPath = ready.contains(edge.fromSlotKey)
                            context.stroke(
                                path,
                                with: .color(isReadyPath ? Color.tfGreen.opacity(0.8) : Color.tfDim.opacity(0.65)),
                                lineWidth: isReadyPath ? 1.5 : 1
                            )
                        }
                    }

                    ForEach(entries) { entry in
                        if let place = places[entry.slotKey] {
                            Button { onTap(entry.slotKey) } label: {
                                node(entry, state: displayState(entry, ready: ready))
                            }
                            .buttonStyle(.plain)
                            .frame(width: place.width, height: nodeHeight)
                            .position(place.center)
                            .accessibilityIdentifier("plan-node-\(entry.slotKey)")
                        }
                    }
                }
                .frame(width: canvasWidth, height: graphHeight)
                }
            }
            .frame(height: graphHeight)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Граф зависимостей плана совместной работы")
        }
    }

    @ViewBuilder
    private func node(_ entry: Entry, state: String) -> some View {
        ZStack(alignment: .topTrailing) {
            TFAvatar(
                size: .lg,
                initials: initials(for: entry.title),
                tint: Color.tfCard2,
                accessibilityLabel: "Аватар: \(entry.title)",
                userID: "role_\(entry.roleKey)"
            )
            .frame(width: nodeWidth, height: nodeHeight)
            Group {
                switch state {
                case "waiting":
                    Text("zz").tfText(.caption).fontWeight(.semibold)
                case "active":
                    Image(systemName: "hammer.fill").symbolEffect(.wiggle, options: .repeating, isActive: !reduceMotion)
                case "accepted":
                    Image(systemName: "checkmark")
                case "blocked", "returned":
                    Image(systemName: "exclamationmark")
                case "review":
                    Image(systemName: "eye")
                case "skipped":
                    Image(systemName: "minus")
                case "ready":
                    Circle().fill(Color.tfGreen).frame(width: 6, height: 6)
                default:
                    EmptyView()
                }
            }
            .foregroundStyle(stateColor(state))
            .font(.caption2)
            .padding(3)
        }
        .frame(width: nodeWidth, height: nodeHeight)
        .overlay(alignment: .bottom) {
            if !entry.taskNumbers.isEmpty {
                Text(entry.taskNumbers.map { $0 == 0 ? "⌂" : String($0) }.joined(separator: ","))
                    .tfText(.caption).foregroundStyle(Color.tfSub)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.title), \(stateLabel(state)), задачи \(entry.taskNumbers.map(String.init).joined(separator: ", "))")
        .accessibilityHint("Открыть задание и действия")
    }

    /// Уровень шага — самый длинный путь от корня: шаги одного уровня идут
    /// параллельно и стоят в одном ряду. Раскладка годится для любого плана,
    /// в том числе достроенного по ходу (раньше — только для full_cycle,
    /// остальное вытягивалось в колонку).
    private var levels: [String: Int] {
        if entries.contains(where: \.isParticipant) {
            return Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($0.element.slotKey, $0.offset / 3) })
        }
        var memo: [String: Int] = [:]
        let incoming = Dictionary(grouping: edges, by: \.toSlotKey)
        func level(_ slot: String, _ path: Set<String>) -> Int {
            if let known = memo[slot] { return known }
            guard !path.contains(slot) else { return 0 }
            let preds = incoming[slot]?.map(\.fromSlotKey) ?? []
            let value = preds.map { level($0, path.union([slot])) + 1 }.max() ?? 0
            memo[slot] = value
            return value
        }
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.slotKey, level($0.slotKey, [])) })
    }

    private var graphHeight: CGFloat {
        if entries.contains(where: \.isParticipant) { return 280 }
        let rows = (levels.values.max() ?? 0) + 1
        return nodeHeight + CGFloat(rows - 1) * rowStep
    }

    private func layout(width: CGFloat) -> [String: (center: CGPoint, width: CGFloat)] {
        if entries.contains(where: \.isParticipant) {
            let radius = min(104, max(60, width / 2 - 36))
            return Dictionary(uniqueKeysWithValues: entries.enumerated().map { index, entry in
                let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * .pi / CGFloat(max(entries.count, 1))
                return (entry.slotKey, (center: CGPoint(x: width / 2 + radius * cos(angle), y: 140 + radius * sin(angle)), width: nodeWidth))
            })
        }
        let levelOf = levels
        let rows = Dictionary(grouping: entries, by: { levelOf[$0.slotKey] ?? 0 })
        var result: [String: (center: CGPoint, width: CGFloat)] = [:]
        for (row, items) in rows {
            let count = CGFloat(items.count)
            let gap = TFSpacing.sm
            let nodeWidth = self.nodeWidth
            let total = nodeWidth * count + gap * (count - 1)
            var x = (width - total) / 2 + nodeWidth / 2
            let y = nodeHeight / 2 + CGFloat(row) * rowStep
            for item in items {
                result[item.slotKey] = (CGPoint(x: x, y: y), nodeWidth)
                x += nodeWidth + gap
            }
        }
        return result
    }

    /// Directed curves use opposite sides for reciprocal edges. Their end
    /// points follow the tangents, so arrowheads remain outside the avatars.
    private func participantConnection(from source: CGPoint, to target: CGPoint) -> Path {
        let dx = target.x - source.x, dy = target.y - source.y
        let distance = max(1, hypot(dx, dy))
        let bend = min(44, distance * 0.28)
        let control = CGPoint(x: (source.x + target.x) / 2 - dy / distance * bend,
                              y: (source.y + target.y) / 2 + dx / distance * bend)
        func port(_ center: CGPoint, toward point: CGPoint) -> CGPoint {
            let length = max(1, hypot(point.x - center.x, point.y - center.y))
            return CGPoint(x: center.x + (point.x - center.x) / length * 40,
                           y: center.y + (point.y - center.y) / length * 40)
        }
        let start = port(source, toward: control), end = port(target, toward: control)
        let tangentLength = max(1, hypot(end.x - control.x, end.y - control.y))
        let ux = (end.x - control.x) / tangentLength, uy = (end.y - control.y) / tangentLength
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        path.move(to: CGPoint(x: end.x - ux * 6 - uy * 3, y: end.y - uy * 6 + ux * 3))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: end.x - ux * 6 + uy * 3, y: end.y - uy * 6 - ux * 3))
        return path
    }

    private func initials(for title: String) -> String {
        let words = title.split(separator: " ")
        return words.prefix(2).compactMap(\.first).map(String.init).joined()
    }

    private func stateLabel(_ state: String) -> String {
        CollaborationPlanView.stateLabel(state)
    }

    private func stateColor(_ state: String) -> Color {
        switch state {
        case "ready": .tfGreen
        case "active": .tfOrange
        case "blocked", "returned": .tfOrange
        case "review": .tfSub
        case "accepted": .tfGreen
        case "skipped": .tfDim
        default: .tfSub
        }
    }
}
