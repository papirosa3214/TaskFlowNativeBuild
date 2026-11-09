import Foundation

/// Ссылка в ответе роли: как её показать.
///
/// Владелец 10.11.2026: «вид нужен и визуал отображения всяких ссылок».
/// В T3 Code ссылка не голый синий текст: у внешнего хоста своя иконка, у
/// файла — иконка и короткое имя со строкой, у темы TaskFlow — свой значок
/// (`apps/mobile/src/lib/markdownLinks.ts`, `native/useEnrichedLinkVariants.ts`).
/// Правила вынесены из вью в чистую функцию: их проверяет целевой тест
/// (`Tools/test_chat_link_presentation.py`), а не глаза на телефоне.
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

    struct Presentation: Equatable {
        let kind: Kind
        /// Подпись: то, что видно вместо длинного адреса.
        let label: String
        let icon: Icon
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
        // Путь к файлу в подписи — тоже осмысленно, его оставляем.
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
        } else if let scheme = URL(string: href)?.scheme {
            // Прочие схемы — не файл.
            if scheme.count > 1 { return nil }
        }
        let (cleaned, line) = splitLine(path)
        guard looksLikeFilePath(cleaned) else { return nil }
        let name = (cleaned as NSString).lastPathComponent
        let label = line.map { name + ":" + String($0) } ?? name
        return Presentation(kind: .file(path: cleaned, line: line), label: label,
                            icon: .symbol("doc.text"))
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

    /// Похоже ли на путь к файлу, а не на слово.
    static func looksLikeFilePath(_ path: String) -> Bool {
        guard path.contains("/") else { return false }
        let last = (path as NSString).lastPathComponent
        guard let dot = last.lastIndex(of: "."), dot != last.startIndex else {
            return path.hasSuffix("/")
        }
        let ext = last[last.index(after: dot)...]
        return ext.count >= 1 && ext.count <= 6 && ext.allSatisfy { $0.isLetter || $0.isNumber }
    }
}
