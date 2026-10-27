import Foundation

/// Рабочая папка чата (`GET/PUT /api/chats/:id/workspace`,
/// LOCK-CHAT-WORKSPACE-20261027). Выбор — из папок проектов на сервере;
/// репозиторий сервера роль правит в своей копии на ветке `branch`.
struct ChatWorkspaceState: Decodable, Sendable, Equatable {
    struct Option: Decodable, Sendable, Equatable, Identifiable {
        let name: String
        let git: Bool
        /// Репозиторий сервера: роль работает в копии, не в живом дереве.
        let copy: Bool
        var id: String { name }
        /// Подпись под названием в меню.
        var subtitle: String? { copy ? "копия, ветка своя" : nil }
    }

    /// nil — по умолчанию: домашняя папка роли.
    let selected: String?
    let branch: String?
    let options: [Option]

    var title: String { selected ?? "Папка" }
}
