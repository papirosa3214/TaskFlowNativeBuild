import SwiftUI

/// Содержимое панели «Комнаты» в корне раздела «Чаты» (владелец 21.10.2026,
/// схема `docs/2026-10-21-chats-rooms-and-sessions.md` в New-Todoist).
///
/// Все роли и пункт «Групповые чаты», куда входит и Общая. Пока две роли переписываются, у обеих горит облачко
/// одного цвета — цвет берётся от ключа пары, поэтому одинаков на обоих
/// концах. Зелёная точка — роль прямо сейчас делает ход.
struct ChatRoomsPanel: View {
    let snapshot: ChatRoomsSnapshot?
    /// Избранные комнаты: только они видны, пока панель не раскрыта целиком
    /// (владелец 08.11.2026: «зажать иконку — и она точно здесь появляется,
    /// а остальные скрытые, пока не раскрою»).
    let favorites: Set<String>
    /// Раскрыт весь список, а не только избранное.
    let showsAll: Bool
    /// Сколько столбцов аватарок: 1 или 2 — зависит от числа комнат.
    let columns: Int
    let onToggleFavorite: (String) -> Void
    let onToggleAll: () -> Void
    let onOpenRole: (ChatRoomsSnapshot.RoleRoom) -> Void
    let onOpenGroups: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var scalePercent: CGFloat = 100
    /// Вкладку тянут за упор — аватарки растягиваются вместе с ней.
    @Environment(\.chatEdgeRailStretch) private var stretch
    private var avatarSide: CGFloat { (ChatEdgeRailMetrics.avatar.rawValue * scalePercent / 100).rounded() }
    private var visibleIDs: [String] { ChatRoomsRail.visibleIDs(snapshot, favorites: favorites, showsAll: showsAll) }
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(avatarSide), spacing: ChatRoomsRail.gap), count: max(1, columns))
    }

    var body: some View {
        VStack(spacing: ChatRoomsRail.gap) {
            if let snapshot {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: gridColumns, spacing: ChatRoomsRail.gap) {
                        ForEach(visibleIDs, id: \.self) { id in
                            if id == ChatRoomsRail.groupsID {
                                groupsButton
                            } else if let role = snapshot.roles.first(where: { $0.id == id }) {
                                roleButton(role)
                            }
                        }
                    }
                    .padding(.horizontal, ChatRoomsRail.padding)
                }
                .scrollBounceBehavior(.basedOnSize)
                if ChatRoomsRail.hasHidden(snapshot, favorites: favorites, showsAll: showsAll) {
                    allToggle
                }
            } else {
                TFLoading(.block)
                    .padding(.vertical, ChatRoomsRail.padding)
            }
        }
        .padding(.vertical, ChatRoomsRail.padding)
        .frame(maxWidth: .infinity)
    }

    private func roleButton(_ role: ChatRoomsSnapshot.RoleRoom) -> some View {
        Button { onOpenRole(role) } label: { roleAvatar(role).scaleEffect(1 + stretch) }
            .buttonStyle(.plain)
            .accessibilityLabel(snapshot.map { label(for: role, in: $0) } ?? role.name)
            .accessibilityIdentifier("chats.rooms.\(role.id)")
            .accessibilityAddTraits(favorites.contains(role.id) ? [.isSelected] : [])
            .onLongPressGesture(minimumDuration: ChatRoomsRail.longPress) {
                onToggleFavorite(role.id)
            }
    }

    private var groupsButton: some View {
        Button(action: onOpenGroups) {
            TFGroupAvatar(identity: ChatRoomsRail.groupsID, size: ChatEdgeRailMetrics.avatar)
                .scaleEffect(1 + stretch)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Групповые чаты")
        .accessibilityIdentifier("chats.rooms.groups")
        .onLongPressGesture(minimumDuration: ChatRoomsRail.longPress) {
            onToggleFavorite(ChatRoomsRail.groupsID)
        }
    }

    /// Полоска внизу: тап раскрывает все комнаты, второй — прячет лишние.
    private var allToggle: some View {
        Button(action: onToggleAll) {
            Capsule()
                .fill(Color.tfSub.opacity(0.45))
                .frame(width: 26, height: 3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, TFSpacing.xs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsAll ? "Только избранные" : "Все комнаты")
        .accessibilityIdentifier("chats.rooms.allToggle")
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

/// Геометрия панели комнат: сколько комнат видно, в сколько столбцов и каких
/// размеров вкладка (владелец 08.11.2026: «по высоте в зависимости от
/// количества персонажей… хотя бы в две строки»).
enum ChatRoomsRail {
    static let groupsID = "chats.groups"
    static let gap: CGFloat = TFSpacing.xs
    static let padding: CGFloat = TFSpacing.sm
    /// Долгое нажатие на аватарку — комната уходит в избранное или обратно.
    static let longPress: Double = 0.45
    static let toggleHeight: CGFloat = 16
    static let maxHeight: CGFloat = 520

    static func allIDs(_ snapshot: ChatRoomsSnapshot?) -> [String] {
        guard let snapshot else { return [] }
        return snapshot.roles.map(\.id) + [groupsID]
    }

    /// Избранное первым, остальное — в порядке панели.
    static func visibleIDs(_ snapshot: ChatRoomsSnapshot?, favorites: Set<String>, showsAll: Bool) -> [String] {
        let all = allIDs(snapshot)
        // Пока ничего не выбрано, прятать нечего: показываем всех.
        guard !favorites.isEmpty, !showsAll else { return all }
        return all.filter { favorites.contains($0) }
    }

    static func hasHidden(_ snapshot: ChatRoomsSnapshot?, favorites: Set<String>, showsAll: Bool) -> Bool {
        !favorites.isEmpty && !showsAll && allIDs(snapshot).contains { !favorites.contains($0) }
    }

    /// Два столбца — только когда комнат много и они раскрыты все.
    static func columns(count: Int, showsAll: Bool) -> Int {
        showsAll && count > 4 ? 2 : 1
    }

    static func width(columns: Int) -> CGFloat {
        let side = ChatEdgeRailMetrics.avatar.rawValue
        let count = CGFloat(max(1, columns))
        return side * count + gap * (count - 1) + padding * 2
    }

    static func height(items: Int, columns: Int, hasToggle: Bool) -> CGFloat {
        let side = ChatEdgeRailMetrics.avatar.rawValue
        let count = CGFloat(max(1, columns))
        let rows = max(1, ceil(CGFloat(max(1, items)) / count))
        var height = padding * 2
        height += gap + rows * side + (rows - 1) * gap
        if hasToggle { height += toggleHeight }
        return min(height, maxHeight)
    }
}
