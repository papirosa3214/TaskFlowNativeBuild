import SwiftUI

// Строка задачи для ProjectTasksScreen — дубль `src/components/TaskRow.tsx`
// (общий компонент, которым пользуется чужой набор экранов), тем же приёмом
// дублирования, что `Features/Planner/PlannerTaskRow.swift` уже применил для
// «Сегодня» («точность спеки важнее переиспользования» — комментарий того
// файла). Не беру TodayTaskRow как есть: этому экрану нужен подавленный
// бейдж проекта (`showProjectBadge=false` — сам экран уже внутри одного
// проекта). Кнопка закрепления в строке жила здесь до 11.09.2026, когда
// владелец её убрал: закрепление переехало в меню «…» карточки задачи.
//
// ⚠️ Сверено с живым `TaskRow.tsx` 31.08.2026: `ProjectTasksScreen.tsx`
// вызывает `<TaskRow .../>` БЕЗ пропа `overdue` — он там всегда `false` по
// умолчанию, то есть просроченные задачи здесь показывают ОБЫЧНый бейдж
// срока (день+месяц, «· N дней»), а не красную пилюлю «Просрочено» — это не
// упрощение, так in the реальном коде, красная пилюля тут в принципе
// недостижима. Верхний файловый комментарий самого TaskRow.tsx про
// «точку-переключатель статуса» — устаревшая документация: в актуальном
// JSX такой кнопки уже нет (проверено построчно), дот-toggle реально
// существует только в LabelTasksScreen (см. её отдельную реализацию).
struct DirectoryTaskRow: View {
    /// Уникальный id задачи (короткий префикс UUID), чтобы владелец мог
    /// ссылаться на конкретную карточку в чате с исполнителем («посмотри
    /// #b6b57092»). Полный UUID слишком длинный, а в мобильном интерфейсе
    /// скопировать строку нельзя — префикс из 8 hex-символов достаточно
    /// уникален в пределах проекта (коллизия по первым 8 символам UUID
    /// практически невозможна при текущем количестве задач).
    let index: String?
    let task: ApiTask
    let isOwner: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void
    /// Контекстное действие на правом свайпе: поднять флаг / принять ревью.
    let swipeAction: ProjectTaskSwipeAction?
    let onSwipeAction: () -> Void

    /// Необязательная строка «роль · модель» (LOCK-177). Заполняется только
    /// на «Работе агентов»; у остальных списков остаётся пустой и ничего не
    /// меняет. `var` с дефолтом, чтобы не трогать существующие вызовы.
    var agentLine: String? = nil

    /// Тап по аватару родительской задачи — раскрыть/свернуть дочерние. `nil` —
    /// у задачи нет дочерних, аватар не ловит нажатие, строка открывается как раньше.
    var onAvatarTap: (() -> Void)? = nil

    /// Рисовать ли аватарку исполнителя (LOCK 11.10.2026, «Активность»).
    /// `false` — строка без кружка, строка уже и без того компактная, а на
    /// «Активности» их десятки: каждый кружок с портретом роли — это ещё и
    /// видеоплеер (`AVPlayerLayer`+`AVPlayerLooper`, LOCK-TEAM-AVATAR-ANIMATION),
    /// и список выполненных задач подвешивал приложение (проверено спиндампом
    /// симулятора: 199 потоков, 20 видеоконвертеров, главный поток не отвечал).
    /// По умолчанию `true` — прежнее поведение остальных списков.
    var showsAvatar: Bool = true

    /// Слова подтверждения свайпа вправо. `nil` — дефолт «Отправить в архив»,
    /// как у обычного списка. Экран «Архив» переиспользует ту же строку для
    /// безвозвратного удаления и подставляет свои слова (10.10.2026).
    var deleteConfirmTitle: String? = nil
    var deleteConfirmMessage: ((String) -> String)? = nil

    /// Зачёркивать ли название выполненной задачи (LOCK 11.10.2026, экран
    /// «Активность»). `nil` — прежнее поведение: зачёркивание выводится из
    /// `task.status`. На «Активности» задачи по определению выполнены, и
    /// зачёркнутый список читался как «остановленное»: владелец не видел, что
    /// именно надо вернуть в работу. Там передаётся `false`.
    var strikesDoneTitle: Bool? = nil

    /// Подпись времени в строке меток (LOCK 11.10.2026, «Активность»): час
    /// закрытия задачи. `nil` — не показывать, прежнее поведение всех
    /// остальных списков. Нужен именно здесь: у строки выполненной задачи
    /// время закрытия — главное, ради чего список сгруппирован по дням.
    var timestamp: String? = nil

    @State private var confirmDelete = false

    var body: some View {
        swipeBody
        // Диалог остался только для окончательного удаления с экрана «Архив»
        // (там владелец передаёт `deleteConfirmTitle`). Обычный свайп в архив
        // его больше не показывает — поручение владельца 12.10.2026.
        .confirmationDialog(deleteConfirmTitle ?? "Отправить задачу в архив?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(deleteConfirmTitle == nil ? "В архив" : "Удалить окончательно", role: .destructive, action: onDelete)
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(deleteConfirmMessage?(task.title)
                ?? "«\(task.title)» будет отправлена в архив. Её можно восстановить.")
        }
    }

    @ViewBuilder
    private var swipeBody: some View {
            row
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        if deleteConfirmTitle == nil { onDelete() } else { confirmDelete = true }
                    } label: {
                        Label(deleteConfirmTitle == nil ? "В архив" : "Удалить окончательно", systemImage: "archivebox")
                    }
                    .tint(Color.tfSwipeDelete)
                    .accessibilityLabel(deleteConfirmTitle == nil ? "В архив" : "Удалить окончательно")
                    .accessibilityIdentifier("directory.swipe.delete")
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
            TFTaskRowContent(title: task.title, description: task.description, isDone: strikesDoneTitle ?? (task.status == .completed)) {
                if showsAvatar, let initials = task.rowAvatarInitials {
                    TFAvatar(size: .taskList, initials: initials, tint: Color(hex: task.assigneeColor ?? TFHexDefault.unassigned), userID: task.rowAvatarID, teamIDs: task.rowAvatarTeam, urlPath: task.rowAvatarURL, teamURLs: task.rowAvatarTeamURLs, portrait: task.rowAvatarPortrait)
                        .contentShape(Rectangle())
                        .highPriorityGesture(TapGesture().onEnded { onAvatarTap?() }, including: onAvatarTap == nil ? .none : .all)
                }
            } metadata: {
                // Даты — в начале метро-ряда: срок есть у каждой задачи, а
                // остальные метки — не у всех, и из-за них дата сдвигалась по
                // строке. Обе даты (срок и дата заведения) стоят рядом — одна
                // колонка (владелец 22.10.2026).
                if let due = task.dueDate {
                    TFDueChip(plain: DirectoryDate.formatDuePlain(due), relative: DirectoryDate.formatDaysLeft(due), days: DirectoryDate.daysUntil(due), overdueText: "Просрочено, \(DirectoryDate.formatDuePlain(due))", highlight: task.status == .active)
                        .layoutPriority(1)
                }
                // Дата и время заведения заявки — пиксельной меткой в квадратных
                // скобках (LOCK-TASK-CREATED-STAMP, владелец 12.10.2026).
                TFTaskCreatedStamp(createdAt: task.createdAt)
                if let timestamp, !timestamp.isEmpty {
                    Text(timestamp).layoutPriority(-1)
                }
                TFTaskStructureIndicators(priority: TaskPriority(rawValue: task.priority), subtasksDone: task.listSubtasksDone, subtasksTotal: task.listSubtasksTotal, childrenCount: task.childrenCount, hasCollaborationPlan: task.hasCollaborationPlan)
                if task.needsResearch {
                    TFPill("Исследование", color: .tfSub, solidBackground: .tfCard)
                }
                if let status = DirectoryAgentStateTag.text(task) {
                    Text(status).foregroundStyle(DirectoryAgentStateTag.color(task)).layoutPriority(-1)
                }
                if task.agentState == .review, task.criticApproved == true { TFCriticApprovedMark() }
                if let index {
                    // Кегль и вес — ступенью (было сырое `.system(.caption)` 12
                    // regular, тогда как весь мета-ряд вокруг — `.caption` 11
                    // medium): размер правится в шкале (LOCK-TYPOGRAPHY-UNIFY).
                    Text("#" + index).tfText(.caption).monospaced()
                }
                if let agentLine, !agentLine.isEmpty {
                    Label(agentLine, systemImage: "cpu")
                }
                ForEach(task.labels, id: \.id) { label in
                    TFLabelPill(label.name, color: Color(hex: label.color ?? TFHexDefault.unassigned)).layoutPriority(-1)
                }
            }
        }
        .buttonStyle(TFTapRowStyle())
        .accessibilityIdentifier("directory.task.\(task.id)")
    }


}

/// Статус агента плоским текстом — дубль `TodayAgentStateTag` (`Features/Planner/PlannerFilters.swift`,
/// чужой файл), те же тексты/цвета AGENT-PROTOCOL.md.
enum DirectoryAgentStateTag {
    static func text(_ task: ApiTask) -> String? {
        if task.isArchived { return task.status == .completed ? "Выполнена" : "Отменена" }
        guard let state = task.listAgentState else { return nil }
        return TFAgentStateTag.text(state, stale: task.agentStale == true)
    }

    static func color(_ task: ApiTask) -> Color {
        if task.isArchived { return .tfSub }
        guard let state = task.listAgentState else { return .tfTeal }
        return TFAgentStateTag.color(state, stale: task.agentStale == true)
    }
}


/// Контекстное действие на свайпе влево (открывается кнопка справа).
/// Решение: владелец видит разное действие в зависимости от того, готов
/// ли он отдать задачу (флаг) или уже отдал (тогда можно сразу принять).
enum ProjectTaskSwipeAction: Equatable {
    /// Завершить задачу (зелёная галочка). Показывается для ВСЕХ
    /// не-завершённых задач с поднятым флагом готовности — владелец 11.09.2026
    /// попросил «если флаг поднят и задача не выполнена, всё равно чтобы
    /// галочка была зелёная принять». Покрывает и ревью (снимает блокировку),
    /// и просто активную задачу в пуле.
    case complete
    /// Вернуть задачу из архива в работу (10.10.2026, экран «Архив»).
    /// Отличается от `.complete` темп��м: свайп влево у архивной строки
    /// означает восстановление, а не закрытие задачи.
    case restore

    /// Полномочия владельца ничем не ограничены (08.11.2026: «у меня
    /// полномочия не ограничены… создать задачу и сразу её отправить в
    /// выполненный, и вообще-то никого ебать не должно»). Флаг готовности
    /// (`ready_for_pickup`) и исполнитель — внутренние регуляторы ролей и
    /// сервера: они решают, кто и когда берёт задачу в работу, но не решают,
    /// показывать ли владельцу кнопку. Поэтому «Принять» есть на каждой живой
    /// задаче в любом состоянии агента.
    ///
    /// `currentUserID` сохранён в сигнатуре ради существующих вызовов и
    /// проверок, но на выбор действия больше не влияет: до 08.11.2026 сданная
    /// на приёмку задача (двойная галочка критика) без поднятого флага и не на
    /// владельце оставалась без свайпа — закрыть её можно было только из
    /// карточки.
    static func action(for task: ApiTask, isOwner: Bool, currentUserID: String? = nil) -> Self? {
        guard isOwner else { return nil }
        guard task.status == .active else { return nil }
        return .complete
    }

    var icon: String {
        switch self {
        case .complete: "checkmark"
        case .restore: "arrow.uturn.backward"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .complete: "Принять"
        case .restore: "Вернуть в работу"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .complete: "project.row.swipe.complete"
        case .restore: "archive.row.swipe.restore"
        }
    }
}
