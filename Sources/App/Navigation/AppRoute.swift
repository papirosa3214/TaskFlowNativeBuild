import Foundation

/// Маршруты приложения — 1:1 таблице «Имена корневых вью» из
/// `spec/INTEGRATION.md`. Каждый case и его параметры совпадают буквально с
/// тем, что описано в контракте (`taskID`, `noteID`, `projectID`, `labelID`) —
/// это то, что писатели экранов ждут от навигации по правилу контракта
/// «переход на другой экран — через маршрут из таблицы».
///
/// `/inbox` сознательно отсутствует — маршрут убран из веба 26.08.2026,
/// нативного аналога нет (см. INTEGRATION.md).
public enum AppRoute: Hashable {
    /// Совместимый маршрут: после объединения 06.09 «Сегодня» открывает
    /// первый раздел единого «Планирования».
    case today
    case overview
    case upcoming
    case timeline
    case chat
    case taskDetail(taskID: String)
    /// `nil` — создание новой задачи, иначе правка существующей.
    case taskForm(taskID: String?)
    case notes
    /// Дневник, сразу открытый на конкретной папке (просьба владельца
    /// 03.09.2026: шеврон «Документация» у проекта вёл на общий несвязанный
    /// корень Заметок — не та папка, что показана в превью карточки проекта).
    /// `.notes` без параметра НЕ трогаем — контракт `INTEGRATION.md` его
    /// таким и описывает, этот case — целенаправленное добавление сверх него.
    case noteFolder(folderID: Int)
    case noteEditor(noteID: String)
    case projects
    /// Смысловой поиск по документации всех проектов (KnowledgeScreen).
    case knowledge
    case projectTasks(projectID: String)
    case labels
    case labelTasks(labelID: String)
    case search
    case activity
    case notifications
    case agents
    case agentWork
    case settings
    case integrations
    case templates
    case voiceModels
}
