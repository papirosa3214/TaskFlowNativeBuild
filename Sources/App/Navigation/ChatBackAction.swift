import SwiftUI

// Выход из чата. На экране чата нижняя панель вкладок скрыта (владелец
// 01.09.2026: «когда я на чате, скрывать основную мою панель, чтобы панель
// ввода оставалась»), поэтому вернуться можно только стрелкой в его шапке —
// а чат сам не знает, откуда в него пришли. Действие кладёт корневой экран,
// чат его только вызывает.
private struct ChatBackActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var chatBackAction: (() -> Void)? {
        get { self[ChatBackActionKey.self] }
        set { self[ChatBackActionKey.self] = newValue }
    }

    /// Положить маршрут в стек текущей вкладки. Нужен там, где
    /// `NavigationLink` не годится — например, пункт меню «…»: ссылка внутри
    /// `Menu` срабатывает ненадёжно (владелец 20.10.2026, «Чаты проектов»).
    var openRoute: ((AppRoute) -> Void)? {
        get { self[OpenRouteKey.self] }
        set { self[OpenRouteKey.self] = newValue }
    }
}

private struct OpenRouteKey: EnvironmentKey {
    static let defaultValue: ((AppRoute) -> Void)? = nil
}
