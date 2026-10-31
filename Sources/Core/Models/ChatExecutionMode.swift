import Foundation

/// How work is delivered. Independent of planning, goal and research settings.
public enum ChatExecutionMode: String, Codable, CaseIterable, Sendable {
    case chat, card

    public var title: String { self == .chat ? "В чате" : "По карточке" }

    /// Значок для блока в окне сессии и в меню панели ввода.
    public var symbol: String {
        self == .chat ? "bubble.left.and.bubble.right" : "checklist"
    }

    /// Одна строка пояснения под названием: что именно меняется.
    public var summary: String {
        self == .chat
            ? "Разговор: ответы здесь, карточки задачи не трогаем"
            : "Работа по карточке: роль ведёт задачу и меняет её состояние"
    }

    public static func resolve(stored: Self?, taskID: String?, parentChatID: String?) -> Self {
        stored ?? (taskID != nil && parentChatID != nil ? .card : .chat)
    }
}
