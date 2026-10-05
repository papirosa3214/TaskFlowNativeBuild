import SwiftUI
import UIKit

/// Роль в выборе исполнителя шага.
struct PlanRoleOption: Identifiable, Hashable {
    let key: String
    let title: String
    var id: String { key }
}

/// Шаг живого плана глазами владельца (01.10.2026): что делает роль, чего
/// ждёт, кто и зачем добавил шаг, и — пока шаг не начат — правка,
/// пропуск, удаление. Сданный и идущий шаг только читается: это история.
struct PlanStepDetailSheet: View {
    let node: ApiCollaborationPlanNode
    var assignments: [ApiCollaborationPlanNode] = []
    var onSelectAssignment: (String) -> Void = { _ in }
    let plan: ApiCollaborationPlan
    let subtask: ApiSubtask?
    let roleTitle: (String) -> String
    let stateLabel: String
    let isEditable: Bool
    let onEdit: () -> Void
    let onSkip: (String) -> Void
    let onRemove: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var isSkipPromptOpen = false
    @State private var skipReason = ""
    @State private var isLiveExpanded = false
    @State private var isRemoveConfirmOpen = false
    @State private var copiedResult = false
    @State private var isPreviousResultExpanded = false

    private var disclosureKey: String { "task.slot.\(node.taskId ?? plan.taskId).\(node.sourceSlotKey ?? node.slotKey)" }

    init(node: ApiCollaborationPlanNode, assignments: [ApiCollaborationPlanNode] = [],
         onSelectAssignment: @escaping (String) -> Void = { _ in }, plan: ApiCollaborationPlan,
         subtask: ApiSubtask?, roleTitle: @escaping (String) -> String, stateLabel: String,
         isEditable: Bool, onEdit: @escaping () -> Void, onSkip: @escaping (String) -> Void,
         onRemove: @escaping () -> Void) {
        self.node = node; self.assignments = assignments; self.onSelectAssignment = onSelectAssignment
        self.plan = plan; self.subtask = subtask; self.roleTitle = roleTitle; self.stateLabel = stateLabel
        self.isEditable = isEditable; self.onEdit = onEdit; self.onSkip = onSkip; self.onRemove = onRemove
        let key = "task.slot.\(node.taskId ?? plan.taskId).\(node.sourceSlotKey ?? node.slotKey)"
        _isLiveExpanded = State(initialValue: TaskCardDisclosureState.flag(key + ".live", default: false))
        _isPreviousResultExpanded = State(initialValue: TaskCardDisclosureState.flag(key + ".previous", default: false))
    }

    private var predecessors: [String] {
        plan.edges.filter { $0.toSlotKey == node.slotKey }.map(\.fromSlotKey)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Роль") {
                        Text(roleTitle(node.roleKey)).foregroundStyle(colorScheme == .light ? Color.tfSub : .secondary)
                    }
                    if stateLabel == "В работе" {
                        DisclosureGroup(isExpanded: Binding(get: { isLiveExpanded }, set: { value in
                            isLiveExpanded = value
                            TaskCardDisclosureState.saveFlag(value, key: disclosureKey + ".live")
                        })) {
                            if isLiveExpanded {
                                TaskLiveActivityView(taskID: node.taskId ?? plan.taskId)
                            }
                        } label: {
                            LabeledContent("Состояние") {
                                Text(stateLabel).foregroundStyle(colorScheme == .light ? Color.tfSub : .secondary)
                            }
                        }
                        .accessibilityIdentifier("plan-state-live")
                    } else {
                        LabeledContent("Состояние") {
                            Text(stateLabel).foregroundStyle(colorScheme == .light ? Color.tfSub : .secondary)
                        }
                    }
                    if let iteration = node.iteration, iteration > 0 {
                        LabeledContent("Круг доработки") {
                            Text("\(iteration)").foregroundStyle(colorScheme == .light ? Color.tfSub : .secondary)
                        }
                    }
                    if assignments.count > 1 {
                        Picker("Поручение", selection: Binding(get: { node.slotKey }, set: onSelectAssignment)) {
                            ForEach(assignments) { item in
                                Text(item.taskTitle ?? item.expectedResult).tag(item.slotKey)
                            }
                        }
                    }
                }
                Section {
                    if !assignmentLines.isEmpty {
                        detailRow("Задание", lines: assignmentLines)
                    }
                    if let expected = cleaned(node.expectedResult) {
                        detailRow("Ожидаемый результат", lines: [expected])
                    }
                    if !predecessors.isEmpty {
                        detailRow("Начнётся после", lines: predecessors.map { title(of: $0) })
                    }
                    if let origin = originLine {
                        detailRow("Откуда шаг", lines: [origin] + (cleaned(node.addedReason).map { [$0] } ?? []))
                    }
                    if let reason = cleaned(node.skipReason) {
                        detailRow("Пропущен", lines: [reason])
                    }
                }
                if let result = subtask?.result, !result.isEmpty, !node.isSkipped {
                    Section {
                        HStack {
                            Text(stateLabel == "В работе" ? "Предыдущий результат" : "Результат")
                                .tfText(.meta).foregroundStyle(Color.tfSub)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = result
                                copiedResult = true
                            } label: {
                                Image(systemName: copiedResult ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(copiedResult ? "Скопировано" : "Скопировать результат")
                            .accessibilityIdentifier("plan-result-copy")
                        }
                        if stateLabel == "В работе" {
                            DisclosureGroup("Показать предыдущий результат", isExpanded: Binding(get: { isPreviousResultExpanded }, set: { value in
                                isPreviousResultExpanded = value
                                TaskCardDisclosureState.saveFlag(value, key: disclosureKey + ".previous")
                            })) {
                                Text(result).textSelection(.enabled)
                            }
                        } else {
                            Text(result).textSelection(.enabled)
                        }
                    }
                    .onChange(of: result) { copiedResult = false }
                }
                if isEditable {
                    Section {
                        Button { onEdit() } label: { Label("Изменить шаг", systemImage: "pencil") }
                            .accessibilityIdentifier("plan-step-edit")
                        if plan.status == "approved" || plan.branchSnapshot != nil {
                            Button { isSkipPromptOpen = true } label: { Label("Пропустить", systemImage: "forward") }
                                .accessibilityIdentifier("plan-step-skip")
                        }
                        Button(role: .destructive) { isRemoveConfirmOpen = true } label: {
                            Label("Удалить шаг", systemImage: "trash")
                        }
                        .accessibilityIdentifier("plan-step-remove")
                    } footer: {
                        Text("Шаг ещё не начат — его можно менять. Порядок сохранится: те, кто ждал этот шаг, будут ждать его предшественников.")
                            .foregroundStyle(colorScheme == .light ? Color.tfSub : .secondary)
                    }
                }
            }
            .navigationTitle(roleTitle(node.roleKey))
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color.tfText)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
            .alert("Почему пропускаем?", isPresented: $isSkipPromptOpen) {
                TextField("Причина", text: $skipReason)
                Button("Пропустить") { onSkip(skipReason) }
                    .disabled(skipReason.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Пропуск виден в плане отдельно от сдачи — причина нужна, чтобы потом было понятно, почему шаг не делали.")
            }
            .confirmationDialog("Удалить шаг «\(roleTitle(node.roleKey))»?", isPresented: $isRemoveConfirmOpen, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { onRemove() }
            }
        }
    }

    /// Смысловые поля сохраняются, одинаковый текст не печатается повторно.
    private var assignmentLines: [String] {
        let expected = cleaned(node.expectedResult)
        var lines: [String] = []
        for text in [node.taskTitle, node.instructions].compactMap({ cleaned($0) }) {
            if text != expected && !lines.contains(text) { lines.append(text) }
        }
        return lines
    }

    private func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func detailRow(_ label: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text(label).tfText(.meta).foregroundStyle(Color.tfSub)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line).tfText(.action).foregroundStyle(Color.tfText).textSelection(.enabled)
            }
        }
        .padding(.vertical, TFSpacing.xs)
    }

    private var originLine: String? {
        switch node.origin {
        case "role": return "Добавила роль: \(addedByTitle)"
        case "rework": return "Доработка по замечаниям: \(addedByTitle)"
        case "owner": return "Добавили вы"
        default: return nil
        }
    }

    private var addedByTitle: String {
        guard let id = node.addedBy else { return "—" }
        return id.hasPrefix("role_") ? roleTitle(String(id.dropFirst(5))) : id
    }

    private func title(of slot: String) -> String {
        guard let other = plan.nodes.first(where: { $0.slotKey == slot }) else { return slot }
        return "\(roleTitle(other.roleKey)) — \(other.expectedResult)"
    }
}

/// Новый шаг или правка неначатого: роль, что сдать, задание, после каких
/// шагов начинать (и, для нового, каких ещё не начатых шагов он раньше).
struct PlanStepEditorSheet: View {
    enum Mode: Equatable {
        case add
        case edit(ApiCollaborationPlanNode)
    }

    let mode: Mode
    let plan: ApiCollaborationPlan
    let roles: [PlanRoleOption]
    /// Шаги, которые ещё не начаты, — только перед ними можно вставить новый.
    let pendingSlots: Set<String>
    let roleTitle: (String) -> String
    let onSave: (ApiPlanOp) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var roleKey = ""
    @State private var expectedResult = ""
    @State private var instructions = ""
    @State private var after: Set<String> = []
    @State private var before: Set<String> = []

    private var editedSlot: String? {
        if case .edit(let node) = mode { return node.slotKey }
        return nil
    }

    private var otherNodes: [ApiCollaborationPlanNode] {
        plan.nodes.filter { $0.slotKey != editedSlot && !$0.isSkipped }
    }

    private var canSave: Bool {
        !roleKey.isEmpty && !expectedResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Роль", selection: $roleKey) {
                        ForEach(roles) { role in
                            Text(role.title).tag(role.key)
                        }
                    }
                    .accessibilityIdentifier("plan-step-role")
                    TextField("Что сдать", text: $expectedResult, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityIdentifier("plan-step-expected")
                    TextField("Задание (необязательно)", text: $instructions, axis: .vertical)
                        .lineLimit(2...8)
                }
                if !otherNodes.isEmpty {
                    Section {
                        ForEach(otherNodes) { node in
                            Toggle(isOn: binding(node.slotKey, in: $after)) {
                                stepLabel(node)
                            }
                        }
                    } header: {
                        Text("Начать после")
                    } footer: {
                        Text("Ничего не выбрано — шаг начнётся сразу, параллельно остальным.")
                            .foregroundStyle(colorScheme == .light ? Color.tfSub : .secondary)
                    }
                }
                if mode == .add {
                    let candidates = otherNodes.filter { pendingSlots.contains($0.slotKey) && !after.contains($0.slotKey) }
                    if !candidates.isEmpty {
                        Section {
                            ForEach(candidates) { node in
                                Toggle(isOn: binding(node.slotKey, in: $before)) {
                                    stepLabel(node)
                                }
                            }
                        } header: {
                            Text("Раньше шагов")
                        } footer: {
                            Text("Эти шаги дождутся нового. Например, дизайнер между аналитиком и разработчиком.")
                            .foregroundStyle(colorScheme == .light ? Color.tfSub : .secondary)
                        }
                    }
                }
            }
            .navigationTitle(mode == .add ? "Новый шаг" : "Шаг плана")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color.tfText)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(!canSave)
                        .accessibilityIdentifier("plan-step-save")
                }
            }
            .onAppear(perform: fill)
        }
    }

    private func stepLabel(_ node: ApiCollaborationPlanNode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(roleTitle(node.roleKey))
            Text(node.expectedResult)
                .font(.caption)
                .foregroundStyle(Color.tfSub)
                .lineLimit(2)
        }
    }

    private func binding(_ slot: String, in set: Binding<Set<String>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(slot) },
            set: { on in
                if on { set.wrappedValue.insert(slot) } else { set.wrappedValue.remove(slot) }
            }
        )
    }

    private func fill() {
        switch mode {
        case .add:
            roleKey = roles.first?.key ?? ""
        case .edit(let node):
            roleKey = node.roleKey
            expectedResult = node.expectedResult
            instructions = node.instructions ?? ""
            after = Set(plan.edges.filter { $0.toSlotKey == node.slotKey }.map(\.fromSlotKey))
        }
    }

    private func save() {
        let expected = expectedResult.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let orderedAfter = plan.nodes.map(\.slotKey).filter { after.contains($0) }
        switch mode {
        case .add:
            onSave(ApiPlanOp(op: "add_step", roleKey: roleKey, expectedResult: expected,
                             instructions: task.isEmpty ? nil : task, after: orderedAfter,
                             before: plan.nodes.map(\.slotKey).filter { before.contains($0) }))
        case .edit(let node):
            onSave(ApiPlanOp(op: "update_step", slotKey: node.slotKey, roleKey: roleKey, expectedResult: expected,
                             instructions: task, after: orderedAfter))
        }
        dismiss()
    }
}
