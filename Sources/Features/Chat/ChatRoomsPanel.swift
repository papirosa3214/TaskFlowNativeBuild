import SwiftUI

/// Содержимое панели «Комнаты» в корне раздела «Чаты» (владелец 21.10.2026,
/// схема `docs/2026-10-21-chats-rooms-and-sessions.md` в New-Todoist).
///
/// Сверху Общая, ниже все роли: личная комната каждой с владельцем и её
/// лички с коллегами. Пока две роли переписываются, у обеих горит облачко
/// одного цвета — цвет берётся от ключа пары, поэтому одинаков на обоих
/// концах. Зелёная точка — роль прямо сейчас делает ход.
struct ChatRoomsPanel: View {
    let snapshot: ChatRoomsSnapshot?
    let onOpenCommon: () -> Void
    let onOpenRole: (ChatRoomsSnapshot.RoleRoom) -> Void

    @ScaledMetric(relativeTo: .subheadline) private var scalePercent: CGFloat = 100
    private var avatarSide: CGFloat { (ChatEdgeRailMetrics.avatar.rawValue * scalePercent / 100).rounded() }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TFSpacing.md) {
                if let snapshot {
                    Button(action: onOpenCommon) {
                        TFGroupAvatar(identity: snapshot.common.chatID, size: ChatEdgeRailMetrics.avatar)
                            .overlay(alignment: .topTrailing) {
                                if snapshot.common.live { RoomLinkBadge(color: Color.tfTeal, side: avatarSide) }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(snapshot.common.live ? "Общая комната, идёт разговор" : "Общая комната")
                    .accessibilityIdentifier("chats.rooms.common")

                    ForEach(snapshot.roles) { role in
                        Button { onOpenRole(role) } label: { roleAvatar(role) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(label(for: role, in: snapshot))
                            .accessibilityIdentifier("chats.rooms.\(role.id)")
                    }
                } else {
                    ProgressView().padding(.top, TFSpacing.md)
                }
            }
            .padding(.vertical, TFSpacing.md)
            .frame(maxWidth: .infinity)
        }
    }

    private func roleAvatar(_ role: ChatRoomsSnapshot.RoleRoom) -> some View {
        RoleMemberAvatar(member: role.member, size: ChatEdgeRailMetrics.avatar)
            .overlay(alignment: .topTrailing) {
                if let link = role.liveDMs.first {
                    RoomLinkBadge(color: RoomLinkPalette.color(for: link.pair), side: avatarSide)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if role.working {
                    Circle()
                        .fill(Color.tfGreen)
                        .frame(width: avatarSide * 0.26, height: avatarSide * 0.26)
                        .overlay { Circle().strokeBorder(Color.tfBackground, lineWidth: 2) }
                }
            }
    }

    private func label(for role: ChatRoomsSnapshot.RoleRoom, in snapshot: ChatRoomsSnapshot) -> String {
        var parts = [role.name]
        if role.working { parts.append("работает") }
        let peers = role.liveDMs.compactMap { snapshot.role($0.peerID)?.name }
        if !peers.isEmpty { parts.append("на связи с: " + peers.joined(separator: ", ")) }
        return parts.joined(separator: ", ")
    }
}

/// Облачко диалога над аватаром: пара ролей переписывается.
struct RoomLinkBadge: View {
    let color: Color
    let side: CGFloat

    var body: some View {
        Image(systemName: "bubble.left.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .frame(width: side * 0.42, height: side * 0.42)
            .shadow(color: Color.tfBackground, radius: 1)
            .offset(x: side * 0.08, y: -side * 0.08)
            .accessibilityHidden(true)
    }
}

/// Цвет облачка от ключа пары: одинаковый у обеих ролей разговора.
enum RoomLinkPalette {
    private static let colors: [Color] = [.tfBlue, .tfPurple, .tfOrange, .tfPink, .tfTeal, .tfCoral]

    static func color(for pair: String) -> Color {
        // Swift Hasher засевается заново в каждом процессе — нужен свой хэш.
        let hash = pair.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return colors[Int(hash % UInt64(colors.count))]
    }
}
