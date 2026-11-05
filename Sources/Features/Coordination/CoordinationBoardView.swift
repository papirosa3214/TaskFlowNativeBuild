import SwiftUI
import Observation

/// Этап полотна глазами владельца: узел плана плюс его подзадача.
struct CoordinationStage: Identifiable {
    let node: ApiCollaborationPlanNode
    let subtask: ApiSubtask?
    let stateKey: String
    /// Этап ещё не начат: его можно менять, а другие могут его ждать.
    let isPending: Bool

    var id: String { node.slotKey }
    var label: String { CollaborationPlanView.stateLabel(stateKey) }
    var isDone: Bool { subtask?.done == true || stateKey == "accepted" }
    var isSkipped: Bool { node.isSkipped }
    var needsOwner: Bool { stateKey == "blocked" || stateKey == "returned" }
    var isActive: Bool { stateKey == "active" || stateKey == "review" }

    var result: String? {
        guard !isSkipped, let text = subtask?.displayResult?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    /// Состояние пишется словом; цвет только у самого слова.
    var tint: Color {
        switch stateKey {
        case "accepted": .tfGreen
        case "active": .tfBlue
        case "review": .tfPurple
        case "blocked", "returned": .tfOrange
        case "ready": .tfTeal
        default: .tfDim
        }
    }
}

/// Данные полотна: план, подзадачи и правки. Общие у «Координации» и Mission Control.
@MainActor @Observable
final class CoordinationBoardModel {
    let planState = CollaborationPlanState()
    var applying = false
    var errorMessage: String?
    /// Шаги дочерних карточек: в плане ветки у узлов чужие подзадачи.
    private var childSubtasks: [ApiSubtask] = []
    /// Изменения кода по веткам: своя карточка и дочерние. Пустые не показываем.
    var codeChanges: [TaskCodeChanges] = []
    /// Что сделали энричеры и эмбеддинги. Только для владельца.
    var context: TaskContextObservability?
    private var codeChangesLoadedAt: Date?
    private let api = APIClient()

    var plan: ApiCollaborationPlan? { planState.plan }

    /// Менять структуру можно только в своём плане: узлы плана ветки живут
    /// в планах дочерних карточек.
    var ownsStructure: Bool {
        guard let plan else { return false }
        return plan.branchSnapshot == nil && plan.branchTeam == nil
    }

    func load(taskID: String, isOwner: Bool) async {
        await planState.load(taskID: taskID, reloadToken: 0, force: true, isOwner: isOwner)
        guard let plan, plan.branchTeam != nil else {
            childSubtasks = []
            return
        }
        let children = Set(plan.nodes.compactMap(\.taskId)).subtracting([taskID])
        var loaded: [ApiSubtask] = []
        for child in children.sorted() {
            if let steps = try? await api.subtasks(taskId: child) { loaded += steps }
        }
        if childSubtasks != loaded { childSubtasks = loaded }
    }

    /// Дифф считается на сервере дорого, поэтому не чаще раза в две минуты. Смотреть может владелец.
    func loadCodeChanges(taskID: String, force: Bool = false) async {
        if !force, let codeChangesLoadedAt, Date().timeIntervalSince(codeChangesLoadedAt) < 120 { return }
        codeChangesLoadedAt = Date()
        let children = Set(plan?.nodes.compactMap(\.taskId) ?? []).subtracting([taskID]).sorted()
        var loaded: [TaskCodeChanges] = []
        for id in [taskID] + children {
            if let changes = try? await api.taskCodeChanges(taskID: id), !changes.isEmpty { loaded.append(changes) }
        }
        if codeChanges != loaded { codeChanges = loaded }
    }

    func loadContext(taskID: String) async {
        if let fresh = try? await api.taskContextObservability(taskId: taskID), context != fresh { context = fresh }
    }

    func cardTitle(_ taskID: String) -> String? {
        plan?.nodes.first { $0.taskId == taskID }?.taskTitle
    }

    func stage(_ slot: String) -> CoordinationStage? {
        guard let plan, let node = plan.nodes.first(where: { $0.slotKey == slot }) else { return nil }
        return stage(for: node, in: plan)
    }

    /// Этапы в порядке полотна: сверху вниз, слева направо.
    var orderedStages: [CoordinationStage] {
        guard let plan else { return [] }
        return CoordinationBoard.levels(of: plan).flatMap { $0 }.compactMap { stage($0) }
    }

    var pendingSlots: Set<String> { Set(orderedStages.filter(\.isPending).map(\.id)) }

    func roleTitle(_ key: String) -> String {
        planState.roleTitles[key] ?? key
    }

    var roleOptions: [PlanRoleOption] {
        var keys = Set(planState.roleTitles.keys)
        keys.formUnion(plan?.nodes.map(\.roleKey) ?? [])
        return keys.sorted().map { PlanRoleOption(key: $0, title: roleTitle($0)) }
    }

    /// Правка живого плана. Сервер сам заводит подзадачу нового этапа и запускает
    /// её, как только дождался предшественников.
    @discardableResult
    func apply(_ ops: [ApiPlanOp], taskID: String, isOwner: Bool) async -> Bool {
        guard let plan, !applying else { return false }
        applying = true
        defer { applying = false }
        do {
            try await api.applyCollaborationPlanOps(taskId: taskID, planId: plan.id, baseVersion: plan.version, ops: ops)
            await load(taskID: taskID, isOwner: isOwner)
            return true
        } catch {
            errorMessage = error.localizedDescription
            await load(taskID: taskID, isOwner: isOwner)
            return false
        }
    }

    private func stage(for node: ApiCollaborationPlanNode, in plan: ApiCollaborationPlan) -> CoordinationStage {
        let sourcePlan = node.sourcePlanId ?? plan.id
        let sourceSlot = node.sourceSlotKey ?? node.slotKey
        let subtask = (planState.subtasks + childSubtasks)
            .first { $0.collaborationPlanId == sourcePlan && $0.planNodeKey == sourceSlot }
        let state = node.isSkipped
            ? "skipped"
            : node.executionState ?? CollaborationPlanView.baseState(for: subtask, planStatus: plan.status)
        let untouched = subtask.map { !$0.done && $0.agentState == nil } ?? true
        return CoordinationStage(node: node, subtask: subtask, stateKey: state,
                                 isPending: !node.isSkipped && untouched && sourcePlan == plan.id)
    }
}

/// Полотно этапов: сверху вниз, параллельные рядом. Раскладку считает
/// `CoordinationBoard`, владелец меняет план, а не двигает карточки.
struct CoordinationBoardView: View {
    let plan: ApiCollaborationPlan
    let model: CoordinationBoardModel
    /// Показывать плюсы. В Mission Control полотно только для чтения.
    let editable: Bool
    let onSelect: (String) -> Void
    let onAdd: (CoordinationBoard.StepPreset) -> Void

    @ScaledMetric(relativeTo: .footnote) private var cardHeight: CGFloat = 104
    @ScaledMetric(relativeTo: .footnote) private var cardWidth: CGFloat = 164
    @State private var availableWidth: CGFloat = 0

    private var metrics: CoordinationBoard.Metrics {
        CoordinationBoard.Metrics(cardWidth: cardWidth, cardHeight: cardHeight, columnGap: TFSpacing.md,
                                  levelGap: 44, plusSize: 28)
    }

    var body: some View {
        let levels = CoordinationBoard.levels(of: plan)
        let canGrow = editable && CoordinationBoard.canGrow(plan)
        let layout = CoordinationBoard.layout(
            levels: levels, metrics: metrics, editable: canGrow,
            minWidth: max(0, availableWidth - TFSpacing.screenHorizontal * 2)
        )
        let links = CoordinationBoard.visibleLinks(of: plan)
        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                CoordinationLinks(links: links, centers: layout.centers, cardHeight: cardHeight)
                    .stroke(Color.tfDim.opacity(0.5), lineWidth: 1)
                ForEach(levels.flatMap { $0 }, id: \.self) { slot in
                    if let stage = model.stage(slot), let center = layout.centers[slot] {
                        card(stage).position(center)
                    }
                }
                if canGrow { pluses(levels: levels, links: links, layout: layout) }
            }
            .frame(width: layout.size.width, height: layout.size.height)
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.vertical, TFSpacing.xs)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { availableWidth = $0 }
        .accessibilityIdentifier("coord.board")
    }

    private func card(_ stage: CoordinationStage) -> some View {
        Button { onSelect(stage.id) } label: {
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                Text(model.roleTitle(stage.node.roleKey))
                    .tfText(.meta)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(1)
                Text(stage.node.expectedResult)
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text(stage.label)
                    .tfText(.caption)
                    .foregroundStyle(stage.tint)
                    .lineLimit(1)
            }
            .padding(TFSpacing.md)
            .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
            .background(Color.tfCard, in: RoundedRectangle(cornerRadius: TFRadius.lg, style: .continuous))
            .overlay {
                if stage.isActive || stage.needsOwner {
                    RoundedRectangle(cornerRadius: TFRadius.lg, style: .continuous)
                        .strokeBorder(stage.tint, lineWidth: 1)
                }
            }
            .opacity(stage.isSkipped ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coord.node.\(stage.id)")
    }

    @ViewBuilder
    private func pluses(levels: [[String]], links: [CoordinationBoard.Link],
                        layout: CoordinationBoard.Layout) -> some View {
        let pending = model.pendingSlots
        let levelOf = levels.enumerated().reduce(into: [String: Int]()) { result, entry in
            for slot in entry.element { result[slot] = entry.offset }
        }
        // Вставить можно только перед неначатым этапом и только между
        // соседними уровнями: у длинной связи середина попала бы на карточку.
        ForEach(links.filter { pending.contains($0.to) && levelOf[$0.to] == (levelOf[$0.from] ?? -2) + 1 }, id: \.self) { link in
            if let from = layout.centers[link.from], let to = layout.centers[link.to] {
                plus(label: "Вставить этап между") {
                    onAdd(CoordinationBoard.insert(between: link.from, and: link.to))
                }
                .position(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            }
        }
        ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
            if index < layout.besidePlus.count {
                plus(label: "Добавить параллельный этап") {
                    onAdd(CoordinationBoard.beside(level: level, in: plan, pending: pending))
                }
                .position(layout.besidePlus[index])
            }
        }
        if let end = layout.endPlus {
            plus(label: "Добавить этап в конец") { onAdd(CoordinationBoard.atEnd(of: plan)) }
                .position(end)
        }
    }

    private func plus(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus")
                .tfTypeFont(size: 13, weight: .semibold)
                .foregroundStyle(Color.tfSub)
                .frame(width: 28, height: 28)
                .background(Color.tfCard2, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.applying)
        .accessibilityLabel(label)
    }
}

/// Связи между этапами: плавная линия от низа карточки к верху следующей.
private struct CoordinationLinks: Shape {
    let links: [CoordinationBoard.Link]
    let centers: [String: CGPoint]
    let cardHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for link in links {
            guard let from = centers[link.from], let to = centers[link.to] else { continue }
            let start = CGPoint(x: from.x, y: from.y + cardHeight / 2)
            let end = CGPoint(x: to.x, y: to.y - cardHeight / 2)
            let bend = max(12, (end.y - start.y) / 2)
            path.move(to: start)
            path.addCurve(to: end,
                          control1: CGPoint(x: start.x, y: start.y + bend),
                          control2: CGPoint(x: end.x, y: end.y - bend))
        }
        return path
    }
}
