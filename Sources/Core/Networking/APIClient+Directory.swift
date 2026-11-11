import Foundation

// Довесок к `APIClient` для экранов раздела «Справочники» (Directory) — СВОЙ
// файл, а не правка `Core/Networking/APIClient+*.swift` (те чужие, правит
// только каркасный исполнитель). Тот же приём, что `TodayViewModel` уже
// применил для своего `APIClient()` — второй экземпляр безопасен (клиент
// `Sendable`, без состояния, токен читает из Keychain на каждый запрос).
//
// Три вещи здесь — не «добавление функциональности», а ИСПРАВЛЕНИЕ реальных
// расхождений между Core/spec/API.md и живым сервером (проверено чтением
// `server/src/routes/*.ts` 31.08.2026, только чтение):
//
// 1. Поиск. `spec/API.md` §5.6 описывает `/search` как «список задач»
//    (файл Core с поиском удалён 11.09.2026, в `archive/` не заводили).
//    Живой `server/src/routes/search.ts`
//    возвращает `{ tasks, projects, labels }` — ТРИ группы, и живой веб
//    (`src/screens/SearchScreen.tsx`) их так и показывает. Спека
//    здесь просто устарела/неполна — в отчёте оркестратору.
//
// 2. Уведомления. Ошибочный дубль `APIClient.markNotificationRead` убран
//    11.11.2026: путь `PATCH /notifications/:id/read` без тела здесь, в
//    `directoryMarkNotificationRead`; массовый — `POST /notifications/read-all`
//    в `directoryMarkAllNotificationsRead`.
//
// 3. `GET /notes` (список заметок с title/preview) и `GET /projects/:id/docs`
//    (сводка документации проекта) — есть на сервере и в spec/API.md §5.9,
//    но не обёрнуты в Core вовсе (`ApiNote` не несёт `title`/`preview`).
public extension APIClient {

    // MARK: - Поиск (3 группы) — spec/SCREENS-2.md §11, живой search.ts

    // MARK: - Уведомления — пути, которые реально принимает сервер

    /// `PATCH /notifications/:id/read`, без тела — сервер молча игнорирует
    /// присланное тело (маршрут его не читает), поэтому пустой JSON тут не нужен.
    func directoryMarkNotificationRead(id: String) async throws {
        let _: APIOkResponse = try await request(.patch, "/notifications/\(id)/read")
    }

    /// `POST /notifications/read-all` — единственный массовый эндпоинт уведомлений.
    func directoryMarkAllNotificationsRead() async throws {
        let _: APIOkResponse = try await request(.post, "/notifications/read-all")
    }

    /// `GET /system-state?from=` — сводка поломок с начала дня устройства.
    internal func systemState(from: Date) async throws -> SystemState {
        try await request(.get, "/system-state",
                          query: [URLQueryItem(name: "from", value: ISO8601DateFormatter().string(from: from))])
    }

    // MARK: - Заметки: список с превью (для секции «Документация» проекта)

    // MARK: - Документация проекта одним запросом — spec/API.md §5.9,
    // `server/src/routes/notes.ts` (`GET /projects/:id/docs`). Русские ключи
    // «папка»/«подсказка»/«как читать» — буквально из ответа сервера.

    struct DirectoryProjectDocs: Decodable, Sendable {
        public struct ProjectRef: Decodable, Sendable { public let id: String; public let name: String }
        public struct FolderRef: Decodable, Sendable { public let id: Int; public let name: String }
        public struct NoteRef: Decodable, Sendable, Identifiable {
            public let id: String
            public let title: String
            public let preview: String?
            public let updatedAt: String?
            /// В какой папке лежит заметка (для дерева «проект → папки задач → файлы»).
            public let folderId: Int?
            enum CodingKeys: String, CodingKey {
                case id, title, preview
                case updatedAt = "updated_at"
                case folderId = "folder_id"
            }
        }
        /// Подпапка внутри папки документации проекта (папка задачи).
        public struct FolderNode: Decodable, Sendable, Identifiable {
            public let id: Int
            public let parentId: Int?
            public let name: String
            enum CodingKeys: String, CodingKey {
                case id, name
                case parentId = "parent_id"
            }
        }

        public let project: ProjectRef
        public let folder: FolderRef?
        public let notes: [NoteRef]
        /// Нет у старого сервера — тогда список остаётся плоским.
        public let folders: [FolderNode]?
        public let подсказка: String?

        enum CodingKeys: String, CodingKey {
            case project, folder, notes, folders, подсказка
        }
    }

    func directoryProjectDocs(projectId: String) async throws -> DirectoryProjectDocs {
        try await request(.get, "/projects/\(projectId)/docs")
    }
}
