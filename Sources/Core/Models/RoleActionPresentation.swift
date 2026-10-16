import Foundation

/// Presentation of received tool events; never invents executions or splits their status.
struct RoleActionPresentation: Equatable {
    let title: String
    let symbol: String
    var skillName: String? = nil

    static func forStep(_ step: RoleChatLiveStep) -> Self {
        let tool = normalized(step.tool)
        if tool == "read", let name = skillName(in: step.detail) {
            let title: String
            switch step.status {
            case .running: title = "Подключение навыка"
            case .done: title = step.resultReceived ? "Навык подключён" : "Чтение навыка не подтверждено"
            case .error: title = "Ошибка чтения навыка"
            }
            return Self(title: title, symbol: "book.closed", skillName: name)
        }
        return forTool(step.tool, detail: step.detail)
    }

    static func forTool(_ raw: String, detail: String? = nil) -> Self {
        let tool = normalized(raw)
        if tool.hasPrefix("taskflow_") {
            if tool.contains("kb_search") { return Self(title: "База знаний", symbol: "books.vertical") }
            if tool.contains("recall") || tool.contains("remember") { return Self(title: "Память", symbol: "brain") }
            if tool.contains("doc_") || tool.hasSuffix("_docs") { return Self(title: "Документация", symbol: "doc.text") }
            if tool.contains("subtask_done") || tool.contains("taskflow_state") { return Self(title: "Сдача результата", symbol: "checkmark.circle") }
            if tool.contains("comment") { return Self(title: "Комментарий", symbol: "text.bubble") }
            return Self(title: "Трекер", symbol: "checklist")
        }
        switch tool {
        case "read", "read_file": return Self(title: "Чтение", symbol: "doc.text")
        case "write", "write_file": return Self(title: "Запись", symbol: "doc.badge.plus")
        case "edit", "apply_patch": return Self(title: "Правка", symbol: "pencil.line")
        case "grep", "glob", "find", "search": return Self(title: "Поиск", symbol: "magnifyingglass")
        case "ls": return Self(title: "Папка", symbol: "folder")
        case "web_search", "web_fetch", "web": return Self(title: "Веб", symbol: "globe")
        case "test": return Self(title: "Тесты", symbol: "checkmark.seal")
        case "build": return Self(title: "Сборка", symbol: "hammer")
        case "git": return Self(title: "Git", symbol: "arrow.triangle.branch")
        case "bash", "exec_command", "run": return shell(detail)
        default: return Self(title: "Действие", symbol: "gearshape")
        }
    }

    private static func normalized(_ tool: String) -> String {
        tool.lowercased().replacingOccurrences(of: "mcp__taskflow__", with: "taskflow_")
    }

    private static func skillName(in detail: String?) -> String? {
        guard let detail, let range = detail.range(of: #"(?:^|/)skills/([a-z][a-z0-9-]*)/SKILL\.md$"#, options: .regularExpression) else { return nil }
        let components = detail[range].split(separator: "/")
        return components.count >= 3 ? String(components[components.count - 2]) : nil
    }

    private static func shell(_ command: String?) -> Self {
        let fallback = Self(title: "Команда", symbol: "terminal")
        guard let command, !command.contains("<<"), !command.contains("$("), !command.contains("`"),
              let segments = shellSegments(command) else { return fallback }
        var actions: [Self] = []
        for segment in segments {
            let words = segment.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let first = words.first else { continue }
            let executable = (first as NSString).lastPathComponent
            let action: Self
            switch executable {
            case "cd", "pwd", "echo", "printf", "true": continue
            case "cat", "head", "tail", "less": action = Self(title: "Чтение", symbol: "doc.text")
            case "rg", "grep", "find", "fd": action = Self(title: "Поиск", symbol: "magnifyingglass")
            case "ls": action = Self(title: "Папка", symbol: "folder")
            case "git": action = Self(title: "Git", symbol: "arrow.triangle.branch")
            case "xcodebuild":
                action = words.contains(where: { ["test", "test-without-building"].contains($0) })
                    ? Self(title: "Тесты", symbol: "checkmark.seal") : Self(title: "Сборка", symbol: "hammer")
            case "swift":
                guard words.contains("test") || words.contains("build") else { return fallback }
                action = words.contains("test") ? Self(title: "Тесты", symbol: "checkmark.seal") : Self(title: "Сборка", symbol: "hammer")
            case "npm", "pnpm", "yarn", "npx":
                if words.contains(where: { ["test", "vitest", "jest", "playwright"].contains($0) }) { action = Self(title: "Тесты", symbol: "checkmark.seal") }
                else if words.contains("build") || words.contains("tsc") { action = Self(title: "Сборка", symbol: "hammer") }
                else { return fallback }
            default: return fallback
            }
            // Redirection is not a read-only action. Do not label `cat > file` as reading.
            if segment.contains(">") { return fallback }
            if !actions.contains(action) { actions.append(action) }
        }
        guard let first = actions.first else { return fallback }
        return Self(title: actions.map(\.title).joined(separator: " · "), symbol: first.symbol)
    }

    /// Recognize separators only outside quotes. Unknown shell structures retain the terminal label.
    private static func shellSegments(_ command: String) -> [String]? {
        var result: [String] = []; var current = ""; var quote: Character?; var escaped = false
        for char in command {
            if escaped { current.append(char); escaped = false; continue }
            if char == "\\" { current.append(char); escaped = true; continue }
            if let active = quote {
                current.append(char)
                if char == active { quote = nil }
            } else if char == "\"" || char == "'" { quote = char; current.append(char) }
            else if [";", "&", "|", "\n"].contains(char) {
                if !current.trimmingCharacters(in: .whitespaces).isEmpty { result.append(current); current = "" }
            } else { current.append(char) }
        }
        guard quote == nil, !escaped else { return nil }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

#if DEBUG
enum RoleActionPreview {
    static var items: [RoleChatLiveItem] {
        let entries: [(String, String, RoleChatLiveStep.Status)] = [
            ("bash", "cat Sources/Example.swift", .done),
            ("bash", "rg event Sources", .done),
            ("write", "docs/result.md", .done),
            ("edit", "Sources/Example.swift", .done),
            ("read", "/home/maksim/taskflow/roles/researcher/skills/user-research/SKILL.md", .done),
            ("read", "/home/maksim/taskflow/roles/researcher/skills/missing/SKILL.md", .error),
            ("bash", "npm test", .done),
            ("taskflow_kb_search", "Поиск решения в базе знаний", .running)
        ]
        return entries.enumerated().map { index, entry in
            .step(RoleChatLiveStep(id: "action-\(index)", tool: entry.0, detail: entry.1, status: entry.2))
        }
    }
}
#endif

#if DEBUG
extension TaskLiveTurn {
    static func previewActions(taskID: String, subtaskID: String?) -> Self {
        Self(taskID: taskID, subtaskID: subtaskID, runID: "action-preview", complete: false,
             turn: RoleChatLiveTurn(chatID: "actions", userID: "role_researcher", name: "Исследователь", startedAt: nil,
                                    items: RoleActionPreview.items, thinking: nil))
    }
}
#endif
