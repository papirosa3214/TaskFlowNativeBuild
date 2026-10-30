import SwiftUI

/// Содержание чата (владелец 14.10.2026, по образцу): список сообщений по
/// первой строке, тап — лента прокручивается к этому сообщению.
struct RoleChatContentsSheet: View {
    let messages: [RoleChatMessage]
    let currentUserID: String?
    let onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            List(messages.filter { !$0.isSessionMarker && !Self.preview($0.text).isEmpty }) { message in
                Button { onSelect(message.id) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.fromUserID == currentUserID ? "Вы" : (message.fromUserName ?? "Участник"))
                            .tfText(.caption)
                            .foregroundStyle(Color.tfSub)
                        Text(Self.preview(message.text))
                            .tfText(.body)
                            .foregroundStyle(Color.tfText)
                            .lineLimit(2)
                    }
                }
                .accessibilityIdentifier("chat.contents.row")
            }
            .listStyle(.plain)
            .navigationTitle("Содержание")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    /// Первая непустая строка без разметки.
    static func preview(_ text: String) -> String {
        let line = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        return line.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "#>-* "))
    }
}
