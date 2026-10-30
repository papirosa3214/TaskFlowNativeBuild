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
