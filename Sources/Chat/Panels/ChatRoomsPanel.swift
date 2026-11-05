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
    let onOpenGroups: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var scalePercent: CGFloat = 100
    /// Вкладку тянут за упор — аватарки растягиваются вместе с ней.
    @Environment(\.chatEdgeRailStretch) private var stretch
    private var avatarSide: CGFloat { (ChatEdgeRailMetrics.avatar.rawValue * scalePercent / 100).rounded() }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TFSpacing.md) {
                if let snapshot {
                    ForEach(snapshot.roles) { role in
                        Button { onOpenRole(role) } label: { roleAvatar(role).scaleEffect(1 + stretch) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(label(for: role, in: snapshot))
                            .accessibilityIdentifier("chats.rooms.\(role.id)")
                    }
                    Button(action: onOpenGroups) {
                        TFGroupAvatar(identity: "chats.groups", size: ChatEdgeRailMetrics.avatar)
                            .scaleEffect(1 + stretch)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Групповые чаты")
                    .accessibilityIdentifier("chats.rooms.groups")
                    // Общая — внизу, под ролями (владелец 21.10.2026).
                    Button(action: onOpenCommon) {
                        TFGroupAvatar(identity: snapshot.common.chatID, size: ChatEdgeRailMetrics.avatar)
                            .scaleEffect(1 + stretch)
                            .overlay(alignment: .topTrailing) {
                                if snapshot.common.live { RoomLinkBadge(colors: [Color.tfTeal], side: avatarSide) }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(snapshot.common.live ? "Общая комната, идёт разговор" : "Общая комната")
                    .accessibilityIdentifier("chats.rooms.common")

                } else {
                    TFLoading(.block)
                }
            }
            .padding(.vertical, TFSpacing.md)
            .frame(maxWidth: .infinity)
        }
    }

    private func roleAvatar(_ role: ChatRoomsSnapshot.RoleRoom) -> some View {
        // Роль делает ход — аватарка играет ролик (как в строке комнаты),
        // зелёной точки «работает» больше нет (владелец 27.10.2026).
        RoleMemberAvatar(member: role.member, size: ChatEdgeRailMetrics.avatar)
            .environment(\.tfAvatarLiveTurn, role.working)
            .overlay(alignment: .topTrailing) {
                // Одно облачко, поделённое на полосы — по цвету каждого живого
                // собеседника, до трёх: пара видна на обоих концах (21.10.2026).
                let links = Array(role.liveDMs.prefix(3))
                if !links.isEmpty {
                    RoomLinkBadge(colors: links.map { RoomLinkPalette.color(for: $0.pair) }, side: avatarSide)
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

/// Облачко диалога над аватаром: роль переписывается. Одно облачко,
/// поделённое по вертикали на полосы — по цвету каждого собеседника.
struct RoomLinkBadge: View {
    let colors: [Color]
    let side: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                Rectangle().fill(color)
            }
        }
        .mask {
            Image(systemName: "bubble.left.fill")
                .resizable()
                .scaledToFit()
        }
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
