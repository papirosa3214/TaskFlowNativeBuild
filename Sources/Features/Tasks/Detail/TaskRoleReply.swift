import SwiftUI

/// Same JSON renderer as chat, without reparsing ordinary journal text as rich content.
struct TaskRoleReply: View {
    let text: String
    var isRole = true
    var rendersLegacyMarkdown = true
    /// Только серверные блоки; при их отсутствии показывается ошибка получения.
    var serverBlocks: [ChatServerBlock]? = nil

    var body: some View {
        if isRole && rendersLegacyMarkdown {
            RoleReplyMarkdown(text: text, serverBlocks: serverBlocks)
        } else {
            Text(text).tfText(.body).foregroundStyle(Color.tfText).textSelection(.enabled)
        }
    }
}
