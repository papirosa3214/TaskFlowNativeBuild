import Foundation

/// Ссылка в ответе роли: как её показать.
///
/// Владелец 10.11.2026: «а можно прям как вот тут отражаются — было бы идеально».
/// В T3 Code ссылка на файл рисуется иконкой языка (питон, свифт, TS, PDF…), а
/// подпись окрашена цветом языка (`apps/mobile/src/lib/markdownLinks.ts`,
/// иконки — набор pierre). Правила вынесены из вью в чистую функцию: их
/// проверяет целевой тест (`Tools/test_chat_link_presentation.py`).
enum ChatLinkPresentation {
    /// Откуда иконка: файл в каталоге ассетов или системный символ.
    enum Icon: Equatable {
        case asset(String)
        case symbol(String)
    }

    enum Kind: Equatable {
        /// Внешний адрес.
        case external(host: String)
        /// Путь к файлу в проекте (`Sources/…/File.swift:23`).
        case file(path: String, line: Int?)
        /// Ссылка на ветку или сообщение самого TaskFlow.
        case thread
    }

    /// Цвет подписи: ключ палитры (`ChatBadgePalette`).
    enum Tint: String, Equatable {
        case python, swift, typescript, javascript, json, markdown, sql, bash
        case html, css, go, other, pdf, image, video, web, docs, note, file
    }

    struct Presentation: Equatable {
        let kind: Kind
        /// Подпись: то, что видно вместо длинного адреса.
        let label: String
        let icon: Icon
        /// Цвет подписи — у файла по языку, у остальных ссылок нет.
        var tint: Tint? = nil
    }

    /// Иконка по расширению — таблица T3 Code (`markdownLinks.ts`, MIT),
    /// иконки — набор pierre из того же репозитория.
    static let iconByExtension: [String: String] = [
        "7z": "zip", "astro": "astro", "avif": "image", "bash": "bash", "bmp": "image",
        "bz2": "zip", "c": "c", "cc": "cpp", "cpp": "cpp", "css": "css", "csv": "table",
        "cts": "typescript", "cxx": "cpp", "db": "database", "eot": "font", "erb": "ruby",
        "fish": "bash", "gif": "image", "go": "go", "gql": "graphql", "graphql": "graphql",
        "gz": "zip", "h": "c", "hh": "cpp", "hpp": "cpp", "htm": "html", "html": "html",
        "hxx": "cpp", "ico": "image", "icns": "image", "ini": "text", "inl": "cpp",
        "jar": "zip", "jpeg": "image", "jpg": "image", "js": "javascript", "json": "json",
        "jsonc": "json", "jsx": "react", "less": "css", "m4v": "video", "md": "markdown",
        "mdx": "markdown", "mjs": "javascript", "mov": "video", "mp4": "video",
        "mts": "typescript", "png": "image", "py": "python", "pyi": "python",
        "pyw": "python", "pyx": "python", "rake": "ruby", "rar": "zip", "rb": "ruby",
        "rs": "rust", "sass": "sass", "scss": "sass", "sh": "bash", "sql": "database",
        "sqlite": "database", "sqlite3": "database", "svelte": "svelte", "svg": "svg",
        "swift": "swift", "tar": "zip", "tf": "terraform", "tfstate": "terraform",
        "tfvars": "terraform", "tgz": "zip", "ts": "typescript", "tsv": "table",
        "tsx": "react", "txt": "text", "webm": "video", "webp": "image", "woff": "font",
        "woff2": "font", "vue": "vue", "wasm": "wasm", "yaml": "yml", "yml": "yml",
        "zig": "zig", "zip": "zip", "zsh": "bash",
    ]

    /// Иконка по полному имени файла (приоритетнее расширения).
    static let iconByBasename: [String: String] = [
        "agents.md": "agents",
        "claude.md": "claude",
        "dockerfile": "docker",
        "compose.yaml": "docker",
        "compose.yml": "docker",
        "docker-compose.yaml": "docker",
        "docker-compose.yml": "docker",
        "gemfile": "ruby",
        "package.json": "npm",
        "pnpm-lock.yaml": "pnpm",
        "pnpm-workspace.yaml": "pnpm",
        "bun.lock": "bun",
        "bun.lockb": "bun",
        "bunfig.toml": "bun",
        "readme.md": "markdown",
        "tsconfig.json": "typescript",
        "vite.config.ts": "vite",
        "vite.config.js": "vite",
        "webpack.config.js": "webpack",
        "tailwind.config.ts": "tailwind",
        "next.config.js": "nextjs",
        "next.config.ts": "nextjs",
        "biome.json": "biome",
        ".gitignore": "git",
        ".gitattributes": "git",
        ".gitmodules": "git",
        ".zshrc": "bash",
        ".bashrc": "bash",
        ".bash_profile": "bash",
        "rakefile": "ruby",
    ]

    /// Цвет подписи по иконке: подпись окрашена цветом языка, как в T3.
    static func tint(forIcon icon: String) -> Tint {
        switch icon {
        case "python": return .python
        case "swift": return .swift
        case "typescript": return .typescript
        case "react", "vue", "svelte", "nextjs", "astro": return .typescript
        case "javascript": return .javascript
        case "json": return .json
        case "markdown": return .markdown
        case "database": return .sql
        case "bash": return .bash
        case "html": return .html
        case "css", "sass", "tailwind": return .css
        case "go": return .go
        case "image", "svg": return .image
        case "video": return .video
        default: return .file
        }
    }

    /// Иконка файла по его имени.
    static func iconName(forFile name: String) -> String {
        let base = name.lowercased()
        if let exact = iconByBasename[base] { return exact }
        let parts = base.split(separator: ".")
        guard parts.count >= 2 else { return "default" }
        for index in 1..<parts.count {
            if let icon = iconByExtension[parts[index...].joined(separator: ".")] { return icon }
        }
        return "default"
    }

    /// Хосты, у которых в каталоге ассетов лежит своя иконка.
    static let brandIcons: [String: String] = [
        "github.com": "link-github",
        "gitlab.com": "link-gitlab",
        "bitbucket.org": "link-bitbucket",
        "codeberg.org": "link-forgejo",
        "forgejo.org": "link-forgejo",
        "dev.azure.com": "link-azure-devops",
        "gitcafe.com": "link-gitcafe",
        "cursor-origin.com": "link-cursor-origin",
    ]

    /// Сегменты пути репозитория, после которых идёт номер.
    static let issueSegments: Set<String> = ["pull", "pulls", "issues", "merge_requests", "commit", "commits"]

    /// Как показать ссылку. `text` — то, что автор написал в разметке: если он
    /// подписал ссылку осмысленно, подпись не переписываем.
    static func presentation(href: String, text: String = "") -> Presentation? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let file = filePresentation(href: trimmed) { return file }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "taskflow" || scheme == "thread" {
            let label = hasOwnLabel(text, for: trimmed) ? text : "Открыть в TaskFlow"
            return Presentation(kind: .thread, label: label, icon: .symbol("bubble.left"))
        }
        guard scheme == "http" || scheme == "https", let rawHost = url.host?.lowercased() else {
            return nil
        }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        if let asset = brandIcons[host] {
            let label = hasOwnLabel(text, for: trimmed) ? text : repositoryLabel(url: url, host: host)
            return Presentation(kind: .external(host: host), label: label, icon: .asset(asset))
        }
        let label = hasOwnLabel(text, for: trimmed) ? text : externalLabel(url: url, host: host)
        return Presentation(kind: .external(host: host), label: label,
                            icon: .symbol("arrow.up.right.square"))
    }

    /// Подпись осмысленная: не пустая, не сам адрес, не «голый» URL и не длиннее 60 знаков.
    static func hasOwnLabel(_ text: String, for href: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != href, trimmed.count <= 60 else { return false }
        guard !trimmed.lowercased().hasPrefix("http://"),
              !trimmed.lowercased().hasPrefix("https://") else { return false }
        return true
    }

    /// `owner/repo`, `owner/repo#12`, `repo/File.swift` — как в T3.
    static func repositoryLabel(url: URL, host: String) -> String {
        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard parts.count >= 2 else { return parts.first ?? host }
        let repo = parts[0] + "/" + parts[1]
        guard parts.count >= 4 else { return repo }
        let marker = parts[2].lowercased()
        let tail = parts[3]
        if issueSegments.contains(marker) { return repo + "#" + tail }
        if marker == "blob" || marker == "tree" {
            return parts[0] + "/" + (parts.last ?? tail)
        }
        return repo
    }

    /// Адрес без своей иконки: подпись — хост и хвост пути.
    static func externalLabel(url: URL, host: String) -> String {
        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let last = parts.last else { return host }
        if parts.count == 1 { return host + "/" + last }
        return host + "/…/" + last
    }

    /// Путь к файлу в проекте: `Sources/Chat/Foo.swift:23`.
    static func filePresentation(href: String) -> Presentation? {
        var path = href
        if let url = URL(string: href), url.scheme?.lowercased() == "file" {
            path = url.path
        } else if let scheme = URL(string: href)?.scheme, scheme.count > 1 {
            return nil
        }
        let (cleaned, line) = splitLine(path)
        guard looksLikeFilePath(cleaned) else { return nil }
        let name = (cleaned as NSString).lastPathComponent
        let label = line.map { name + ":" + String($0) } ?? name
        let icon = iconName(forFile: name)
        return Presentation(kind: .file(path: cleaned, line: line), label: label,
                            icon: .asset("file-" + icon), tint: tint(forIcon: icon))
    }

    /// Отделить `:строка` (или `:строка:колонка`) от пути.
    static func splitLine(_ raw: String) -> (path: String, line: Int?) {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2, let number = Int(parts[parts.count - 1]) else { return (raw, nil) }
        if parts.count >= 3, Int(parts[parts.count - 2]) != nil {
            return (parts.dropLast(2).joined(separator: ":"), Int(parts[parts.count - 2]))
        }
        return (parts.dropLast().joined(separator: ":"), number)
    }

    /// Похоже ли на путь к файлу, а не на слово. Без каталога файлом считается
    /// только имя с известным расширением или известное имя (`Dockerfile`,
    /// `package.json`), иначе любое слово с точкой стало бы «файлом».
    static func looksLikeFilePath(_ path: String) -> Bool {
        let last = (path as NSString).lastPathComponent
        if !path.contains("/") {
            if iconByBasename[last.lowercased()] != nil { return true }
            let ext = (last as NSString).pathExtension.lowercased()
            return iconByExtension[ext] != nil
        }
        guard let dot = last.lastIndex(of: "."), dot != last.startIndex else {
            return path.hasSuffix("/") || iconByBasename[last.lowercased()] != nil
        }
        let ext = last[last.index(after: dot)...].lowercased()
        return ext.count >= 1 && ext.count <= 8 && ext.allSatisfy { $0.isLetter || $0.isNumber }
    }
}
