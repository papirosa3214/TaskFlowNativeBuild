import SwiftUI
import UniformTypeIdentifiers

/// «Экспорт» чата (владелец 20.10.2026): вся лента одним файлом Markdown
/// через системное «Поделиться». Файл собирается только в момент отправки.
struct RoleChatTranscript: Transferable {
    let title: String
    let messages: [RoleChatMessage]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { transcript in
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(transcript.fileName)
            try transcript.markdown.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }

    var fileName: String {
        let safe = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: " ")
        return (safe.isEmpty ? "Чат" : safe) + ".md"
    }

    var markdown: String {
        var lines = ["# \(title)", ""]
        for message in messages {
            if message.isSessionMarker {
                lines += ["---", "_Новая сессия_", ""]
                continue
            }
            let author = message.fromUserName ?? "Участник"
            let time = message.createdAt.map { " · \($0)" } ?? ""
            lines.append("**\(author)**\(time)")
            if !message.text.isEmpty { lines.append(message.text) }
            for attachment in message.attachments ?? [] { lines.append("📎 \(attachment.fileName)") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Экспорт из списка чатов

/// Экспорт сессий в Markdown прямо из списка (владелец 12.11.2026: «как
/// минимум сессии экспортировать в Markdown, чтобы контекст передавать в
/// другие программы»). Одна сессия — её стенограмма; несколько (папка
/// проекта) — один файл, сессии через разделитель.
enum RoleChatMarkdownExport {
    static func share(title: String, transcripts: [RoleChatTranscript]) throws {
        let markdown: String
        if transcripts.count == 1, let only = transcripts.first {
            markdown = only.markdown
        } else {
            markdown = (["# \(title)", ""] + transcripts.map(\.markdown)).joined(separator: "\n\n---\n\n")
        }
        let file = RoleChatTranscript(title: title, messages: [])
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(file.fileName)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        presentShareSheet(url: url)
    }

    /// Системный лист «Поделиться» — напрямую, а не через `.sheet`: вложенный
    /// в шторку `UIActivityViewController` рисовался серой пустой панелью
    /// (тот же приём, что в заметках).
    private static func presentShareSheet(url: URL) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.keyWindow?.rootViewController
        else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }
}
