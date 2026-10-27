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

    /// На чипе — последнее имя пути: «New-Todoist/server» → «server».
    var title: String { selected.map { ($0 as NSString).lastPathComponent } ?? "Папка" }
}

/// Одна папка в обзоре (`GET /api/chats/:id/workspace/browse?path=`).
struct ChatFolderListing: Decodable, Sendable, Equatable {
    struct Entry: Decodable, Sendable, Equatable, Identifiable {
        let name: String
        /// Путь от корня проектов — его и сохраняет выбор.
        let path: String
        let git: Bool
        var id: String { path }
    }

    /// "" — корень проектов.
    let path: String
    /// Куда «наверх»; nil — уже в корне.
    let parent: String?
    let entries: [Entry]

    var title: String { path.isEmpty ? "Проекты" : (path as NSString).lastPathComponent }
}
