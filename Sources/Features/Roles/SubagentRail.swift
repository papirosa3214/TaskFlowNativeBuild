import SwiftUI

/// Роль, которую позвали субагентом в этом чате (владелец 28.10.2026).
/// `id` — её комната: там вопрос, живой ход и ответ.
struct SubagentRailItem: Identifiable {
    let id: String
    let member: RoleChatMember
    let working: Bool
    let outcome: RoomTurn.Outcome?

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
                                            working: !coordination.terminal,
                                            outcome: outcome(of: coordination))
        }
        return order.compactMap { byRoom[$0] }
    }

    private static func outcome(of coordination: RoleChatCoordination) -> RoomTurn.Outcome? {
        guard coordination.terminal else { return nil }
        switch coordination.status {
        case "answered": return .answered
        case "error": return .failed
        default: return nil
        }
    }
}

/// Содержимое выезжающей панели субагентов — портреты как в панели комнат
/// (`ChatRoomsPanel`): ролик — роль работает, точка — итог её хода.
struct SubagentRailPanel: View {
    let items: [SubagentRailItem]
    let onOpen: (SubagentRailItem) -> Void

    @ScaledMetric(relativeTo: .subheadline) private var scalePercent: CGFloat = 100
    @Environment(\.chatEdgeRailStretch) private var stretch
    private var avatarSide: CGFloat { (ChatEdgeRailMetrics.avatar.rawValue * scalePercent / 100).rounded() }

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
            .overlay(alignment: .bottomTrailing) {
                if !item.working, let outcome = item.outcome {
                    RoomTurnOutcomeDot(outcome: outcome, diameter: avatarSide * 0.26, ringed: true)
                }
            }
    }

    private func label(for item: SubagentRailItem) -> String {
        var parts = [item.member.name]
        if item.working { parts.append("работает") }
        else if let outcome = item.outcome { parts.append(RoomTurnOutcomeDot(outcome: outcome).label) }
        return parts.joined(separator: ", ")
    }
}
