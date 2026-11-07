import SwiftUI

/// Режим чтения использует только готовые блоки сервера.
struct TaskDescriptionRichPreview: View {
    let text: String
    var serverBlocks: [ChatServerBlock]? = nil
    var prepared: [ChatRichSegment]? = nil

    var body: some View {
        RoleReplyMarkdown(text: text, serverBlocks: serverBlocks, prepared: prepared)
    }
}
