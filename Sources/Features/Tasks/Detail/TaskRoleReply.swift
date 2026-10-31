import SwiftUI

/// Same JSON renderer as chat, without reparsing ordinary journal text as rich content.
struct TaskRoleReply: View {
    let text: String
    var isRole = true
    var rendersLegacyMarkdown = true
    /// Текст, уже разобранный сервером; nil — разбор на месте (старый сервер).
    var serverBlocks: [ChatServerBlock]? = nil

    var body: some View {
        if isRole, let json = TaskRoleContent.json(in: text) {
            ChatStructuredOutputView(json: json)
        } else if isRole && rendersLegacyMarkdown && (text.contains("**") || text.contains("\n#") || text.hasPrefix("#") || text.contains("```") || text.contains("\n- ") || text.contains("|---")) {
            RoleReplyMarkdown(text: text, serverBlocks: serverBlocks)
        } else {
            Text(text).tfText(.body).foregroundStyle(Color.tfText).textSelection(.enabled)
        }
    }
}
