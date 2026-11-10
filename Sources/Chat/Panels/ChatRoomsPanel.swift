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

/// Ряд комнат стоит у верхней кромки. Без этого iOS 26 растворяет его кружки.
private struct RoomsStripScrollEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .scrollEdgeEffectHidden(true, for: .top)
                .scrollEdgeEffectHidden(true, for: .bottom)
                .scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            content
        }
    }
}

/// Верхний ряд комнат на экране «Чаты». В покое ряда нет: кружки живут
/// стопкой в шапке (`ChatRoomsHeaderPile`). Потяг вниз вываливает их сюда
/// в линию с именами. Жест — `RoomsRevealPan` на списке.
struct ChatRoomsTopStrip: View {
    let snapshot: ChatRoomsSnapshot?
    let favorites: Set<String>
    let showsAll: Bool
    /// 0 — ряд спрятан в шапку, 1 — кружок и имя.
    var reveal: CGFloat
    let onToggleFavorite: (String) -> Void
    let onToggleAll: () -> Void
    let onOpenRole: (ChatRoomsSnapshot.RoleRoom) -> Void
    let onOpenGroups: () -> Void
    let onToggleReveal: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var scalePercent: CGFloat = 100

    private var revealClamped: CGFloat { min(1, max(0, reveal)) }
    private var avatarSide: CGFloat { (ChatRoomsTopMetrics.avatar * scalePercent / 100).rounded() }
    private var fullHeight: CGFloat { ChatRoomsTopMetrics.topPad + avatarSide + 2 + ChatRoomsTopMetrics.nameHeight }
    private var shownHeight: CGFloat { fullHeight * revealClamped }
    private var visibleIDs: [String] {
        ChatRoomsRail.visibleIDs(snapshot, favorites: favorites, showsAll: showsAll)
    }

    var body: some View {
        row
            .frame(height: fullHeight, alignment: .top)
            .frame(height: shownHeight, alignment: .top)
            .clipped()
            .allowsHitTesting(revealClamped > 0.2)
            .tfScreenBackground()
            .accessibilityElement(children: revealClamped > 0.55 ? .contain : .ignore)
            .accessibilityLabel(revealClamped > 0.55 ? "Комнаты" : "Показать комнаты")
            .accessibilityAction { onToggleReveal() }
            .accessibilityIdentifier("chats.roomsRail")
    }

    @ViewBuilder
    private var row: some View {
        if snapshot == nil {
            TFLoading(.inline)
                .frame(maxWidth: .infinity)
                .padding(.top, ChatRoomsTopMetrics.topPad)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: TFSpacing.sm) {
                    ForEach(visibleIDs, id: \.self) { id in
                        if id == ChatRoomsRail.groupsID {
                            groupsButton
                        } else if let role = snapshot?.roles.first(where: { $0.id == id }) {
                            roleButton(role)
                        }
                    }
                    if ChatRoomsRail.hasHidden(snapshot, favorites: favorites, showsAll: showsAll) {
                        allButton
                    }
                }
                .padding(.horizontal, TFSpacing.md)
                .padding(.top, ChatRoomsTopMetrics.topPad)
                .frame(height: fullHeight, alignment: .top)
            }
            // Кромка iOS 26 гасит содержимое прокрутки у верха экрана. Ряд
            // как раз там: подложка остаётся, кружки становятся прозрачными.
            // Маленькая стопка в шапке — не прокрутка, поэтому её было видно.
            .contentMargins(0, for: .scrollContent)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .modifier(RoomsStripScrollEdge())
        }
    }

    private func roleButton(_ role: ChatRoomsSnapshot.RoleRoom) -> some View {
        Button { onOpenRole(role) } label: {
            VStack(spacing: 2) {
                roleCircle(role)
                Text(role.name)
                    .tfText(.caption)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(1)
                    .frame(width: avatarSide)
                    .opacity(revealClamped)
            }
        }
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
            VStack(spacing: 2) {
                TFGroupAvatar(identity: ChatRoomsRail.groupsID, size: ChatEdgeRailMetrics.avatar)
                    .frame(width: avatarSide, height: avatarSide)
                Text("Группы")
                    .tfText(.caption)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(1)
                    .frame(width: avatarSide)
                    .opacity(revealClamped)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Групповые чаты")
        .accessibilityIdentifier("chats.rooms.groups")
        .onLongPressGesture(minimumDuration: ChatRoomsRail.longPress) {
            onToggleFavorite(ChatRoomsRail.groupsID)
        }
    }

    /// Хвостик ряда: остальные комнаты спрятаны в избранном.
    private var allButton: some View {
        Button(action: onToggleAll) {
            VStack(spacing: 2) {
                Image(systemName: showsAll ? "chevron.up" : "ellipsis")
                    .foregroundStyle(Color.tfText)
                    .frame(width: avatarSide, height: avatarSide)
                Text(showsAll ? "Скрыть" : "Все")
                    .tfText(.caption)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(1)
                    .frame(width: avatarSide)
                    .opacity(revealClamped)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsAll ? "Только избранные" : "Все комнаты")
        .accessibilityIdentifier("chats.rooms.allToggle")
    }

    private func roleCircle(_ role: ChatRoomsSnapshot.RoleRoom) -> some View {
        RoleMemberAvatar(member: role.member, size: ChatEdgeRailMetrics.avatar)
            .environment(\.tfAvatarLiveTurn, role.working)
            .overlay(alignment: .topTrailing) {
                let links = Array(role.liveDMs.prefix(3))
                if !links.isEmpty {
                    RoomLinkBadge(colors: links.map { RoomLinkPalette.color(for: $0.pair) }, side: avatarSide)
                }
            }
            .frame(width: avatarSide, height: avatarSide)
    }

    private func label(for role: ChatRoomsSnapshot.RoleRoom, in snapshot: ChatRoomsSnapshot) -> String {
        var parts = [role.name]
        if role.working { parts.append("работает") }
        let peers = role.liveDMs.compactMap { snapshot.role($0.peerID)?.name }
        if !peers.isEmpty { parts.append("на связи с: " + peers.joined(separator: ", ")) }
        return parts.joined(separator: ", ")
    }
}

/// Свёрнутые комнаты в шапке: три кружка внахалёст, как в Telegram,
/// пока ряд не вытянут вниз.
struct ChatRoomsHeaderPile: View {
    let snapshot: ChatRoomsSnapshot?
    let favorites: Set<String>
    let showsAll: Bool
    /// 0 — стопка на месте, 1 — она уже выпала в ряд и здесь не видна.
    var reveal: CGFloat
    let onOpenRole: (ChatRoomsSnapshot.RoleRoom) -> Void
    let onOpenGroups: () -> Void

    private var revealClamped: CGFloat { min(1, max(0, reveal)) }
    private var ids: [String] {
        Array(ChatRoomsRail.visibleIDs(snapshot, favorites: favorites, showsAll: showsAll).prefix(3))
    }

    var body: some View {
        HStack(spacing: -10) {
            ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                pileItem(id)
                    .zIndex(Double(ids.count - index))
            }
        }
        .opacity(1 - revealClamped)
        .allowsHitTesting(revealClamped < 0.45)
        .accessibilityElement(children: revealClamped < 0.45 ? .contain : .ignore)
        .accessibilityIdentifier("chats.rooms.header")
    }

    @ViewBuilder
    private func pileItem(_ id: String) -> some View {
        if id == ChatRoomsRail.groupsID {
            Button(action: onOpenGroups) {
                TFGroupAvatar(identity: ChatRoomsRail.groupsID, size: .md)
                    .overlay(Circle().strokeBorder(Color.tfBackground, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Групповые чаты")
        } else if let role = snapshot?.roles.first(where: { $0.id == id }) {
            Button { onOpenRole(role) } label: {
                RoleMemberAvatar(member: role.member, size: .md)
                    .environment(\.tfAvatarLiveTurn, role.working)
                    .overlay(Circle().strokeBorder(Color.tfBackground, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(role.name)
        }
    }
}

enum ChatRoomsTopMetrics {
    static let avatar: CGFloat = ChatEdgeRailMetrics.avatar.rawValue
    static let nameHeight: CGFloat = 16
    static let topPad: CGFloat = 6
    static var full: CGFloat { topPad + avatar + 2 + nameHeight }
    /// Весь путь — из шапки в ряд. В покое под шапкой ничего не торчит.
    static var travel: CGFloat { full }
}

/// Потяг списка вниз раскрывает верхний ряд, потяг вверх у верхнего края
/// задвигает его. Горизонталь отдаёт прокрутке аватарок и ленте.
struct RoomsRevealPan: UIGestureRecognizerRepresentable {
    var enabled: Bool
    var atTop: Bool
    var isOpen: Bool
    let onChange: (CGFloat) -> Void
    let onEnd: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        return pan
    }

    func updateUIGestureRecognizer(_ pan: UIPanGestureRecognizer, context: Context) {
        context.coordinator.enabled = enabled
        context.coordinator.atTop = atTop
        context.coordinator.isOpen = isOpen
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let dy = pan.translation(in: nil).y
        switch pan.state {
        case .began, .changed: onChange(dy)
        case .ended: onEnd(dy, pan.velocity(in: nil).y)
        case .cancelled, .failed: onEnd(dy, 0)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var enabled = false
        var atTop = true
        var isOpen = false

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard enabled, let pan = gesture as? UIPanGestureRecognizer else { return false }
            let v = pan.velocity(in: nil)
            guard abs(v.y) > abs(v.x) * 1.15 else { return false }
            if v.y > 0 { return atTop && !isOpen }
            return atTop && isOpen
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView
        }
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
