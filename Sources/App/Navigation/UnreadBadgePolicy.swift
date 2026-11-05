/// Когда бейдж гаснет (владелец 05.11.2026: «он если есть, я перехожу, он не
/// исчезает»). Экран, на котором владелец уже находится, цифру не показывает.
enum UnreadBadgePolicy {
    /// Бейдж вкладки «Сегодня»: гаснет при первом заходе и возвращается на
    /// следующий день.
    static func todayTabCount(dueToday: Int, seenDate: String, today: String, isOnTodayTab: Bool) -> Int {
        isOnTodayTab || seenDate == today ? 0 : dueToday
    }

    /// Какой день записать как просмотренный.
    static func todaySeenDate(current: String, today: String, isOnTodayTab: Bool) -> String {
        isOnTodayTab ? today : current
    }

    /// Цифра на вкладке темы проекта: открытая тема прочитана, даже если
    /// список тем пришёл раньше, чем сервер принял отметку прочтения.
    static func topicCount(unread: Int, isOpen: Bool) -> Int {
        isOpen ? 0 : unread
    }
}
