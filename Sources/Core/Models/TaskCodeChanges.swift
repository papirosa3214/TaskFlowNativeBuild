import Foundation

/// Изменения кода карточки: что роль поменяла в своей ветке `roles/<task_id>`
/// (`GET /api/tasks/:id/code-changes`, LOCK-TASK-CODE-CHANGES-20261027).
/// Владелец 27.10.2026: «точно буду знать, что трогали, что не трогали».
/// Diff разобран на сервере — приложение только показывает строки.
struct TaskCodeChanges: Decodable, Sendable, Equatable {
    enum State: String, Decodable, Sendable {
        /// Ветка ещё не влита.
        case branch
        /// Влита; диапазон — из очереди слияний.
        case merged
        /// Изменений не найти: ветки нет или она пустая.
        case none
    }

    struct Totals: Decodable, Sendable, Equatable {
        let files: Int
        let additions: Int
        let deletions: Int
    }

    let taskID: String
    let branch: String
    let state: State
    let totals: Totals
    let files: [CodeFile]

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case branch, state, totals, files
    }

    var isEmpty: Bool { state == .none || files.isEmpty }

    /// «3 файла · +42 −7» — строка в «Итоге».
    var summary: String {
        TurnCodeChanges(totals: totals, files: files).summary
    }

    static func filesWord(_ count: Int) -> String { plural(count, "файл", "файла", "файлов") }
    static func linesWord(_ count: Int) -> String { plural(count, "строка", "строки", "строк") }

    private static func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod10 = count % 10, mod100 = count % 100
        let word: String
        if mod10 == 1 && mod100 != 11 { word = one }
        else if (2...4).contains(mod10) && !(12...14).contains(mod100) { word = few }
        else { word = many }
        return "\(count) \(word)"
    }
}

/// Файлы, которые роль поменяла за один ход в чате (`steps.code_changes`,
/// сервер с 27.10.2026). У хода нет ветки — только итог правок.
struct TurnCodeChanges: Decodable, Sendable, Equatable {
    let totals: TaskCodeChanges.Totals
    let files: [CodeFile]

    var summary: String {
        "\(TaskCodeChanges.filesWord(totals.files)) · +\(totals.additions) −\(totals.deletions)"
    }
}

struct CodeFile: Decodable, Sendable, Equatable, Identifiable {
    enum Status: String, Decodable, Sendable {
        case added, deleted, modified, renamed, unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .unknown
        }
    }

    let path: String
    let oldPath: String?
    let status: Status
    let additions: Int
    let deletions: Int
    let binary: Bool
    /// Строк больше потолка сервера: показана часть, счётчики — полные.
    let truncated: Bool
    let hunks: [CodeHunk]

    var id: String { path }

    enum CodingKeys: String, CodingKey {
        case path, status, additions, deletions, binary, truncated, hunks
        case oldPath = "old_path"
    }

    var fileName: String { (path as NSString).lastPathComponent }
    var directory: String { (path as NSString).deletingLastPathComponent }

    enum DisplayRow: Equatable {
        case line(CodeLine)
        /// Между кусками правки: «N строк без изменений».
        case gap(Int)
    }

    /// Строки для экрана правки: куски подряд, между ними — пропуск.
    var displayRows: [DisplayRow] {
        var rows: [DisplayRow] = []
        var lastOld: Int?
        for hunk in hunks {
            if let lastOld, let firstOld = hunk.lines.compactMap(\.old).first {
                let gap = firstOld - lastOld - 1
                if gap > 0 { rows.append(.gap(gap)) }
            }
            rows.append(contentsOf: hunk.lines.map(DisplayRow.line))
            lastOld = hunk.lines.compactMap(\.old).last ?? lastOld
        }
        return rows
    }
}

struct CodeHunk: Decodable, Sendable, Equatable {
    let header: String
    let lines: [CodeLine]
}

struct CodeLine: Decodable, Sendable, Equatable, Hashable {
    enum Kind: String, Decodable, Sendable { case context, added, deleted }
    let kind: Kind
    /// Номер в старой версии; у добавленной — nil.
    let old: Int?
    /// Номер в новой версии; у удалённой — nil.
    let new: Int?
    let text: String
}

/// Комментарий владельца к строке правки. Уходит роли комментарием карточки:
/// роль читает комментарии при следующем запуске.
struct CodeReviewComment: Identifiable, Equatable, Sendable {
    let id = UUID()
    let path: String
    let line: CodeLine
    let text: String

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    /// Место в коде словами: файл, строка, что с ней сделано.
    var location: String {
        switch line.kind {
        case .added: return "`\(path)`, строка \(line.new ?? 0) (добавлена)"
        case .deleted: return "`\(path)`, строка \(line.old ?? 0) (удалена)"
        case .context: return "`\(path)`, строка \(line.new ?? line.old ?? 0)"
        }
    }

    /// Одно сообщение роли со всеми замечаниями: файл, строка, код, текст.
    static func message(_ comments: [CodeReviewComment]) -> String {
        let items = comments.map { comment in
            let code = comment.line.text.trimmingCharacters(in: .whitespaces)
            return "- \(comment.location): `\(code)`\n  \(comment.text)"
        }
        return (["Замечания по изменениям кода:"] + items).joined(separator: "\n")
    }
}
