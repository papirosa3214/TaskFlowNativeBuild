import SwiftUI

/// Роль, которую позвали субагентом в этом чате (владелец 28.10.2026).
/// `id` — её комната: там вопрос, живой ход и ответ.
struct SubagentRailItem: Identifiable {
    let id: String
    let member: RoleChatMember
    let working: Bool

    /// Субагенты чата из карточек обращений: одна комната — один портрет,
    /// в порядке первого вызова. Обращения без своей комнаты не показываются.
    static func items(messages: [RoleChatMessage], members: [RoleChatMember], chatID: String) -> [SubagentRailItem] {
        var order: [String] = []
        var byRoom: [String: SubagentRailItem] = [:]
        for message in messages {
            guard let coordination = message.coordination,
                  let room = coordination.childChatID, !room.isEmpty, room != chatID else { continue }
            let recipientID = coordination.recipientID ?? room
            let member = members.first { $0.id == recipientID }
                ?? RoleChatMember(id: recipientID, name: coordination.recipientName,
                                  avatarColor: nil, avatarURL: nil, initials: nil, roleKey: nil)
            if byRoom[room] == nil { order.append(room) }
            byRoom[room] = SubagentRailItem(id: room, member: member,
                                            working: !coordination.terminal)
        }
        return order.compactMap { byRoom[$0] }
    }
}

/// Содержимое выезжающей панели субагентов — портреты как в панели комнат
/// (`ChatRoomsPanel`): ролик — роль работает, точка — итог её хода.
struct SubagentRailPanel: View {
    let items: [SubagentRailItem]
    let onOpen: (SubagentRailItem) -> Void

    @Environment(\.chatEdgeRailStretch) private var stretch

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TFSpacing.md) {
                ForEach(items) { item in
                    Button { onOpen(item) } label: { avatar(item).scaleEffect(1 + stretch) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(label(for: item))
                        .accessibilityIdentifier("chat.subagents.\(item.id)")
                }
            }
            .padding(.vertical, TFSpacing.md)
            .frame(maxWidth: .infinity)
        }
    }

    private func avatar(_ item: SubagentRailItem) -> some View {
        RoleMemberAvatar(member: item.member, size: ChatEdgeRailMetrics.avatar)
            .environment(\.tfAvatarLiveTurn, item.working)
    }

    private func label(for item: SubagentRailItem) -> String {
        var parts = [item.member.name]
        if item.working { parts.append("работает") }
        return parts.joined(separator: ", ")
    }
}
