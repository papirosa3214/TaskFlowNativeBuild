import SwiftUI
import UniformTypeIdentifiers

// `TaskJournal` — spec/SCREENS-2.md §19.2 (тот же случай, что у SubtaskFeed:
// компонент карточки задачи, прямо адресованный этому экрану). Лента
// объединяет комментарии и системные события, новые СВЕРХУ.
//
// Упрощения относительно полной спеки (осознанно, см. отчёт):
// - «живая строка чем занят агент» (тикает раз в 2с) — статичный текст,
//   без опроса `activity.ts` (§5.14, отдельный крупный роут, не читан);
// - `ResumeSessionButton` — не сделан («служебная функциональность, для
//   нативного приложения актуальность уточнить отдельно», сама спека
//   разрешает пропустить);
// - формы владельца (ReturnToWorkSheet) — текстовое поле + отправка, без
//   микрофона/файла (диктовки в этой волне нигде нет, `NATIVE-PARTS.md` §0).
enum TaskJournalEntry: Identifiable {
    case comment(ApiComment)
    case event(ApiTaskEvent)

    var id: String {
        switch self {
        case .comment(let c): "c-\(c.id)"
        case .event(let e): "e-\(e.id)"
        }
    }

    var date: Date? {
        switch self {
        case .comment(let c): c.createdAtDate
        case .event(let e): e.createdAtDate
        }
    }

    /// Сортировка «новые сверху» — spec §19.2.
    static func merged(comments: [ApiComment], events: [ApiTaskEvent]) -> [TaskJournalEntry] {
        (comments.map(TaskJournalEntry.comment) + events.map(TaskJournalEntry.event))
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}

enum AgentOwnerActionKind {
    case acceptReview
    case returnToWorkFromReview
    case replyAndReturnFromBlocked
    case acceptAndClose
    case returnToWorkFromInProgress

    /// spec §7 `commentRequiredFor()` — переходы В blocked/review и
    /// review→in_progress требуют комментарий. Здесь релевантны два случая.
    var commentRequired: Bool {
        switch self {
        case .returnToWorkFromReview, .replyAndReturnFromBlocked: true
        default: false
        }
    }
}

// 11.09.2026: сам экран-лента отсюда удалён (LOCK-120). Он рисовался только
// в `TaskDetailScreen`, а тот был двухстрочной заглушкой — код не
// исполнялся, и починка ленты, внесённая в него, ничего не меняла в
// приложении. Рабочая лента живёт в `TaskFormScreen.nativeJournalRow`.
// Здесь осталось то, что этой рабочей лентой и используется: разбор записей
// (`TaskJournalEntry`), виды владельческих действий и словарь формулировок
// событий.
enum TaskJournalView {
    /// Словарь формулировок §19.2, ДОСЛОВНО. `kind` — открытая строка
    /// (`Core/Models/TaskEvent.swift`), сравниваем как есть.
    static func eventText(_ event: ApiTaskEvent) -> String {
        switch event.kind {
        case "claimed": "взял задачу в работу"
        case "resumed_after_blocked": "вернулся к работе после блокировки"
        case "returned_to_work": "вернул задачу на доработку"
        case "submitted_review": "сдал задачу на проверку"
        case "blocked": "заблокировал задачу — нужны действия владельца"
        case "unclaimed": "снял задачу с агента"
        case "accepted": "принял задачу"
        case "reopened": "вернул задачу в работу"
        case "renamed": "переименовал задачу"
        case "priority_changed": "сменил приоритет"
        case "due_date_set": "поставил срок"
        case "due_date_cleared": "убрал срок"
        case "assigned": "назначил исполнителем"
        case "unassigned": "снял исполнителя"
        case "moved_to_project": "перенёс задачу в проект"
        case "removed_from_project": "убрал задачу из проекта"
        case "subtask_added": "добавил шаг"
        case "subtask_completed": "выполнил шаг"
        case "subtask_uncompleted": "снял отметку с шага"
        case "subtask_renamed": "переименовал шаг"
        case "subtask_deleted": "удалил шаг"
        case "subtask_submitted_review": "сдал шаг на проверку"
        case "subtask_returned": "вернул шаг на доработку"
        case "description_changed": "изменил описание"
        case "labels_changed": "изменил метки"
        case "created": "создал задачу"
        case "subtasks_added": "добавил шаги"
        default: event.kind
        }
    }
}

extension AgentOwnerActionKind: Identifiable {
    var id: Self { self }
}
