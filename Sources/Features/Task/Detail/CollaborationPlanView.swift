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
public struct CollaborationPlanView: View {
    let taskId: String
    /// Родитель прячет весь `Section` целиком, пока плана нет — иначе на
    /// 99% карточек без плана оставалась бы пустая секция с системными
    /// отступами. Обновляется по факту загрузки, не заранее.
    @Binding var hasApprovedPlan: Bool

    @State private var plan: ApiCollaborationPlan?
    @State private var slots: [ApiRoleSlot] = []
    @State private var roleTitles: [String: String] = [:]

    private let api = APIClient()

    public init(taskId: String, hasApprovedPlan: Binding<Bool>) {
        self.taskId = taskId
        self._hasApprovedPlan = hasApprovedPlan
    }

    @State private var didStartLoad = false

    public var body: some View {
        // Пока plan == nil, тело ниже пустое — List не шлёт onAppear
        // пустой ячейке вовсе (проверено на устройстве 28.09.2026). Якорь
        // нулевого размера всегда присутствует в дереве, поэтому lifecycle
        // гарантированно срабатывает.
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear {
                    guard !didStartLoad else { return }
                    didStartLoad = true
                    Task { await load() }
                }
            if let plan {
                content(for: plan)
            }
        }
    }

    @ViewBuilder
    private func content(for plan: ApiCollaborationPlan) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            HStack {
                Text("План совместной работы")
                    .tfText(.caption)
                    .foregroundStyle(Color.tfSub)
                Spacer()
                Text(Self.profileLabel(plan.profile))
                    .tfText(.caption)
                    .foregroundStyle(Color.tfSub)
            }
            ForEach(plan.nodes) { node in
                row(for: node, in: plan)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func row(for node: ApiCollaborationPlanNode, in plan: ApiCollaborationPlan) -> some View {
        let slot = slots.first { $0.planNodeKey == node.slotKey }
        let state = slot?.state ?? "waiting"
        let blockers = state == "waiting" ? predecessors(of: node.slotKey, in: plan) : []

        HStack(spacing: TFSpacing.sm) {
            Text(title(for: node.roleKey))
                .tfText(.meta)
                .foregroundStyle(Color.tfText)
            if !blockers.isEmpty {
                Text("— ждёт: \(blockers.map { title(for: $0.roleKey) }.joined(separator: ", "))")
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(1)
            }
            Spacer()
            Text(Self.stateLabel(state))
                .tfText(.meta)
                .foregroundStyle(Self.stateColor(state))
        }
    }

    private func predecessors(of slotKey: String, in plan: ApiCollaborationPlan) -> [ApiCollaborationPlanNode] {
        plan.edges
            .filter { $0.toSlotKey == slotKey }
            .compactMap { edge in plan.nodes.first { $0.slotKey == edge.fromSlotKey } }
    }

    private func title(for roleKey: String) -> String {
        roleTitles[roleKey] ?? roleKey
    }

    private func load() async {
        async let plansTask = api.collaborationPlans(taskId: taskId)
        async let slotsTask = api.roleSlots(taskId: taskId)
        async let rolesTask = api.roles()
        guard let plans = try? await plansTask else { return }
        slots = (try? await slotsTask) ?? []
        if let roles = try? await rolesTask {
            roleTitles = Dictionary(uniqueKeysWithValues: roles.map { ($0.role, $0.title) })
        }
        plan = plans.first { $0.status == "approved" }
        hasApprovedPlan = plan != nil
    }

    private static func profileLabel(_ profile: String) -> String {
        switch profile {
        case "single_executor": "Один исполнитель"
        case "research": "Исследование"
        case "delivery": "Доставка"
        case "full_cycle": "Полный цикл"
        case "manual": "Вручную"
        default: profile
        }
    }

    private static func stateLabel(_ state: String) -> String {
        switch state {
        case "waiting": "Ждёт"
        case "ready": "Готов к старту"
        case "active": "В работе"
        case "submitted": "Сдано"
        case "accepted": "Принято"
        default: state
        }
    }

    private static func stateColor(_ state: String) -> Color {
        switch state {
        case "ready": .tfBlue
        case "active": .tfOrange
        case "submitted": .tfPurple
        case "accepted": .tfGreen
        default: .tfSub
        }
    }
}
