import Foundation

/// Чем отфильтрован список задач проекта (меню «⋯» в шапке, владелец 06.10.2026).
///
/// Закрытые (выполненные) карточки из живых списков убраны (владелец
/// 01.11.2026: «в архив уходят отменённые и выполненные… из всех остальных
/// списков убрать»), поэтому пунктов «Выполненные» и «Все, включая
/// выполненные» в меню больше нет — закрытые лежат в архиве.
enum ProjectTaskFilter: String, CaseIterable, Identifiable {
    case open, all, working, review, stuck, waiting, blocked
    var id: String { rawValue }
    var title: String {
        switch self {
        case .open: "Открытые"
        case .all: "Все"
        case .waiting: "Ожидающие запуска"
        case .blocked: "Заблокированы"
        case .working: "В работе"
        case .review: "На проверке"
        case .stuck: "Застряли или ждут"
        }
    }
    var icon: String {
        switch self {
        case .open: "circle.dashed"
        case .all: "list.bullet"
        case .waiting: "clock"
        case .blocked: "exclamationmark.triangle"
        case .working: "hammer"
        case .review: "eye"
        case .stuck: "exclamationmark.triangle"
        }
    }
    /// Общий экран показывает ровно четыре независимых состояния и обычные виды списка.
    static let allTasksCases: [Self] = [.open, .working, .review, .blocked, .waiting]

    /// Сама задача подходит под фильтр.
    func matches(_ task: ApiTask) -> Bool {
        switch self {
        case .waiting: TaskVisibility.isLive(task) && (task.listAgentState == nil || task.listAgentState == .todo)
        case .blocked: TaskVisibility.isLive(task) && task.listAgentState == .blocked
        case .open: TaskVisibility.isLive(task)
        case .all: TaskVisibility.isLive(task)
        case .working: TaskVisibility.isLive(task) && task.listAgentState == .inProgress
        case .review: TaskVisibility.isLive(task) && task.listAgentState == .review
        case .stuck: TaskVisibility.isLive(task) && (task.listAgentState == .blocked || task.listAgentState == .todo)
        }
    }
}
