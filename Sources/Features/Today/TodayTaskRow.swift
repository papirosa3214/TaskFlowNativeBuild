import SwiftUI

// Строка задачи со свайпом — spec/SCREENS-1.md §3.3 + живой `TaskRow.tsx`.
//
// НЕ переиспользует `TFTaskRow` из DesignSystem целиком: тот не умеет
// свайп (влево — «Изменить», вправо — «Удалить») и рисует «Просрочено» БЕЗ
// даты, а живой веб-код (TaskRow.tsx, строка ~549) печатает «Просрочено,
// {formatDueLabel}» — точность спеки важнее переиспользования здесь.
// Мелкие бейджи-примитивы (TFPill/TFPriorityFlag/TFAvatar/цвета) взяты из
// DesignSystem как есть. В отчёте — оркестратору свести оба варианта.
struct TodayTaskRow: View {
    let task: ApiTask
    /// Список «Плана» передаёт true для просроченных задач — красная пилюля с датой
    /// вместо обычного бейджа срока (spec: `overdue` проп TaskRow.tsx).
    let overdue: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void
    let swipeAction: TodayTaskSwipeAction?
    /// true — свайп действия строки разрешён только в крайних зонах.
    /// Для обычного экрана «Сегодня» по умолчанию доступна вся строка.
    var swipeOnlyAtEdges: Bool = false
    /// Ширина зоны у каждого края в пунктах.
    var horizontalEdgeZone: CGFloat = HorizontalPanZones.defaultEdgeWidth
    let onSwipeAction: () -> Void

    var body: some View {
            row
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button(role: .destructive, action: onDelete) {
                        Label("В архив", systemImage: "archivebox")
                    }
                    .tint(Color.tfSwipeDelete)
                    .accessibilityLabel("В архив")
                    .accessibilityIdentifier("row.swipe.delete")
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if let swipeAction {
                        Button(action: onSwipeAction) {
                            Label(swipeAction.accessibilityLabel, systemImage: swipeAction.icon)
                        }
                        .tint(Color.tfGreen)
                        .accessibilityLabel(swipeAction.accessibilityLabel)
                        .accessibilityIdentifier(swipeAction.accessibilityIdentifier)
                    }
                }
    }

    private var row: some View {
        Button {
            onOpen()
        } label: {
            TFTaskRowContent(title: task.title, description: task.description, isDone: task.status == .completed) {
                if let initials = task.rowAvatarInitials {
                    TFAvatar(size: .taskList, initials: initials, tint: Color(hex: task.assigneeColor ?? TFHexDefault.unassigned), userID: task.rowAvatarID, teamIDs: task.rowAvatarTeam, urlPath: task.rowAvatarURL, teamURLs: task.rowAvatarTeamURLs, portrait: task.rowAvatarPortrait)
                }
            } metadata: {
                // Даты — в начале метро-ряда: срок есть у каждой задачи, а
                // остальные метки — не у всех, и из-за них дата сдвигалась по
                // строке. Обе даты (срок и дата заведения) стоят рядом — одна
                // колонка (владелец 22.10.2026).
                if let due = task.dueDate {
                    TFDueChip(plain: TodayDate.formatDuePlain(due), relative: TodayDate.formatDaysLeft(due), days: TodayDate.daysUntil(due), overdueText: "Просрочено, \(TodayDate.formatDueLabel(due))", highlight: task.status == .active, forceOverdue: overdue)
                        .layoutPriority(1)
                }
                // Дата и время заведения заявки — пиксельной меткой в квадратных
                // скобках (LOCK-TASK-CREATED-STAMP, владелец 12.10.2026).
                TFTaskCreatedStamp(createdAt: task.createdAt)
                TFTaskStructureIndicators(priority: TaskPriority(rawValue: task.priority), subtasksDone: task.subtasks.isEmpty ? nil : task.subtasks.count { $0.done }, subtasksTotal: task.subtasks.isEmpty ? nil : task.subtasks.count, childrenCount: task.childrenCount, hasCollaborationPlan: task.hasCollaborationPlan)
                if let status = TodayAgentStateTag.text(task) {
                    Text(status).foregroundStyle(TodayAgentStateTag.color(task)).layoutPriority(-1)
                }
                if task.agentState == .review, task.criticApproved == true { TFCriticApprovedMark() }
                if let project = task.projectName {
                    Text("#\(project)").foregroundStyle(Color.tfReadableText(Color(hex: task.projectColor ?? TFHexDefault.unassigned))).layoutPriority(-1)
                }
                ForEach(task.labels, id: \.id) { label in
                    TFLabelPill(label.name, color: Color(hex: label.color ?? TFHexDefault.unassigned)).layoutPriority(-1)
                }
            }
        }
        .buttonStyle(TFTapRowStyle())
        // ⚠️ Порядок важен: `accessibilityElement(children:)` создаёт НОВЫЙ
        // элемент и отбрасывает всё, что задано до него, — идентификатор,
        // поставленный выше, молча пропадал, и тесты не находили строку.
        // Сначала собираем элемент, потом даём ему имя и идентификатор.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel)
        .accessibilityIdentifier("today.task-row")
        // Строка ЯВЛЯЕТСЯ кнопкой, но `children: .ignore` собирает новый
        // элемент и трейт кнопки при этом теряется: в дереве строка
        // становится «Other», VoiceOver не говорит «кнопка», а тесты её не
        // находят среди `app.buttons`. Трейт возвращаем руками.
        .accessibilityAddTraits(.isButton)
    }


    /// Короткое имя для VoiceOver: название задачи, опционально проект и
    /// дата заведения. Без проекта и бейджей — одна строка; с проектом —
    /// «Проект, Задача».
    ///
    /// Дата добавлена с меткой (LOCK-TASK-CREATED-STAMP): строка собрана
    /// `accessibilityElement(children: .ignore)`, то есть всё содержимое, включая
    /// метку, заменяется этой подписью. Без неё дата заведения была бы видна
    /// только глазами — для VoiceOver её просто не существовало бы.
    private var rowAccessibilityLabel: String {
        let base: String
        if let projectName = task.projectName, !projectName.isEmpty {
            base = "\(projectName), \(task.title)"
        } else {
            base = task.title
        }
        guard let spoken = TFTaskCreatedStamp.spokenLabel(forCreatedAt: task.createdAt) else { return base }
        return "\(base), \(spoken)"
    }

}

enum TodayTaskSwipeAction: Equatable {
    case complete
    case acceptReview

    /// `currentUserID` — чтобы у личного дела (исполнитель — сам владелец)
    /// был «Завершить», а не «Запустить»: запускать там некого (23.09.2026).
    static func action(for task: ApiTask, isOwner: Bool, currentUserID: String? = nil) -> Self? {
        guard task.status == .active else { return nil }
        if isOwner, task.agentState == .review { return .acceptReview }
        if let me = currentUserID, task.assigneeId == me { return .complete }
        if isOwner, task.agentState == nil, !task.readyForPickup { return nil }
        return .complete
    }

    var icon: String {
        switch self {
        case .complete, .acceptReview: "checkmark"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .complete: "Завершить"
        case .acceptReview: "Принять"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .complete: "row.swipe.complete"
        case .acceptReview: "row.swipe.accept"
        }
    }
}
