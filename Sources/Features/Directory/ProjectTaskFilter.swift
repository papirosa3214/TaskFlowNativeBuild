import Foundation

/// Чем отфильтрован список задач проекта (меню «⋯» в шапке, владелец 06.10.2026).
enum ProjectTaskFilter: String, CaseIterable, Identifiable {
    case open, all, working, review, stuck, done, waiting, blocked
    var id: String { rawValue }
    var title: String {
        switch self {
        case .open: "Не выполненные"
        case .all: "Все, включая выполненные"
        case .waiting: "Ожидающие запуска"
        case .blocked: "Заблокированы"
        case .working: "В работе"
        case .review: "На проверке"
        case .stuck: "Застряли или ждут"
        case .done: "Выполненные"
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
        case .done: "checkmark.circle"
        }
    }
    /// Общий экран показывает ровно четыре независимых состояния и обычные виды списка.
    static let allTasksCases: [Self] = [.open, .all, .working, .review, .blocked, .waiting]

    /// Сама задача подходит под фильтр.
    func matches(_ task: ApiTask) -> Bool {
        switch self {
        case .waiting: task.status != .completed && (task.listAgentState == nil || task.listAgentState == .todo)
        case .blocked: task.status != .completed && task.listAgentState == .blocked
        case .open: task.status != .completed
        case .all: true
        case .working: task.status != .completed && task.listAgentState == .inProgress
        case .review: task.status != .completed && task.listAgentState == .review
        case .stuck: task.status != .completed && (task.listAgentState == .blocked || task.listAgentState == .todo)
        case .done: task.status == .completed
        }
    }
}
