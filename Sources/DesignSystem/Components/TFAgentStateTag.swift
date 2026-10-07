import SwiftUI

/// Подпись состояния задачи — один источник текста и цвета для списков и
/// шапки карточки (владелец 07.10.2026: «одинаковый статус», образец — списки).
/// `stale` — агент взял работу и замолчал (`agent_stale`).
public enum TFAgentStateTag {
    public static func text(_ state: AgentState, stale: Bool) -> String {
        if state == .inProgress, stale { return "Агент пропал" }
        switch state {
        case .inProgress: return "в работе"
        case .blocked: return "заблокировано"
        case .review: return "на проверке"
        case .todo: return "в очереди"
        }
    }

    public static func color(_ state: AgentState, stale: Bool) -> Color {
        if state == .inProgress, stale { return .tfCoral }
        switch state {
        case .inProgress: return .tfTeal
        case .blocked: return .tfOrange
        case .review: return .tfBlue
        case .todo: return .tfSub
        }
    }
}
