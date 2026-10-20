import SwiftUI

/// Столбец участников у правой кромки чата (владелец 20.10.2026, по образцу
/// стороннего мессенджера). В покое — узкий край во всю высоту свободного
/// места между шапкой и полем ввода, как закладки семьи в карточке задачи
/// (`TaskFamilyEdgeTabs`): тот же цвет листа, красноватый контур и тень.
/// Тянется влево ровно на ширину аватарки и дальше не идёт; смахнул
/// вправо — спрятался. Системное «назад» над панелью не срабатывает —
/// см. `RoleChatRailPan`.
///
/// Тап по аватару — «@Имя» в поле ввода, кому пишем. «+» внизу — добавить
/// участника, зажать аватар — убрать его из чата.
struct RoleChatMembersRail: View {
    let members: [RoleChatMember]
    let addable: [RoleProfile]
    let canManage: Bool
    @Binding var isOpen: Bool
    let onMention: (RoleChatMember) -> Void
    let onAdd: (String) -> Void
    let onRemove: (RoleChatMember) -> Void

    /// Живой сдвиг пальца по горизонтали (вправо — плюс), пока идёт жест.
    @State private var drag: CGFloat = 0
    @State private var isDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let avatar: TFAvatar.Size = .xl
    /// Аватар и по `TFSpacing.sm` с боков — «на размер иконки», не больше.
    static let openWidth: CGFloat = avatar.rawValue + TFSpacing.sm * 2
    static let restingWidth = TaskFamilyEdgeTabs.restingWidth
    /// Запас для пальца левее открытой панели (владелец 20.10.2026): здесь
    /// жест забирает панель, а не системное «назад».
    static let openSlack: CGFloat = TFSpacing.lg
    private static let travel = openWidth - restingWidth

    private var width: CGFloat {
        let raw = (isOpen ? Self.openWidth : Self.restingWidth) - drag
        if raw > Self.openWidth {
            // Дальше аватарки не идёт, но и не упирается: мягкое сопротивление.
            return Self.openWidth + Self.rubberband(raw - Self.openWidth, dimension: Self.openWidth)
        }
        return max(Self.restingWidth, raw)
    }
    private var reveal: CGFloat {
        min(1, (width - Self.restingWidth) / Self.travel)
    }

    var body: some View {
        TaskFamilyEdgeTabs.tabShape
            .fill(TaskFamilyEdgeTabs.fillColor)
            .overlay {
                TaskFamilyTabOutline(openEdge: .trailing)
                    .stroke(TaskFamilyEdgeTabs.outlineColor, lineWidth: TaskFamilyEdgeTabs.outlineWidth)
            }
            .compositingGroup()
            .shadow(color: TaskFamilyEdgeTabs.shadowColor, radius: TaskFamilyEdgeTabs.shadowRadius)
            .overlay(alignment: .leading) {
                RoleChatMembersColumn(members: members, addable: addable, canManage: canManage,
                                      onMention: onMention, onAdd: onAdd, onRemove: onRemove)
                    .frame(width: Self.openWidth)
                    .opacity(reveal)
                    .allowsHitTesting(isOpen && !isDragging)
            }
            .clipShape(Rectangle().inset(by: -TaskFamilyEdgeTabs.shadowRadius * 2))
            .frame(width: width)
            .frame(maxHeight: .infinity)
            // Полоса для пальца шире видимого края, чтобы край ловился;
            // у открытой — запас слева, чтобы смахнуть и не уйти «назад».
            .padding(.leading, isOpen ? Self.openSlack : TaskFamilyEdgeZone.width - Self.restingWidth)
            .contentShape(Rectangle())
            .onTapGesture { if !isOpen { settle(open: true, velocity: 0) } }
            .gesture(RoleChatRailPan(
                onChange: { dx in
                    isDragging = true
                    drag = dx
                },
                onEnd: { dx, vx in finish(translation: dx, velocity: vx) }))
            .sensoryFeedback(.impact(weight: .light), trigger: isOpen)
            .accessibilityElement(children: isOpen ? .contain : .ignore)
            .accessibilityLabel(isOpen ? "Участники чата" : "Показать участников")
            .accessibilityAddTraits(isOpen ? [] : .isButton)
            .accessibilityAction { settle(open: !isOpen, velocity: 0) }
            .accessibilityIdentifier("chat.membersRail")
    }

    /// Решение по отпусканию: бросок решает направлением, медленный жест —
    /// по точке, куда панель доехала бы по инерции. Задвинуть легче, чем
    /// удержать открытой: открытая прячется, если ушла на четверть пути.
    private func finish(translation dx: CGFloat, velocity vx: CGFloat) {
        let open: Bool
        if abs(vx) > Self.flickVelocity {
            open = vx < 0
        } else {
            let base = isOpen ? Self.openWidth : Self.restingWidth
            let projected = base - dx - Self.project(vx)
            let reach = (projected - Self.restingWidth) / Self.travel
            open = isOpen ? reach > 0.75 : reach > 0.3
        }
        settle(open: open, velocity: vx)
    }

    private static let flickVelocity: CGFloat = 300

    /// Доезд пружиной с текущего места и со скоростью пальца — без шва
    /// между жестом и анимацией. Отскок — только после броска.
    private func settle(open: Bool, velocity vx: CGFloat) {
        let distance = (open ? Self.openWidth : Self.restingWidth) - width
        // Ширина растёт, когда палец идёт влево, — отсюда минус.
        let relative = abs(distance) > 0.5 ? -vx / distance : 0
        let spring: Animation = .interpolatingSpring(
            duration: 0.34, bounce: abs(vx) > Self.flickVelocity ? 0.15 : 0, initialVelocity: relative)
        withAnimation(reduceMotion ? nil : spring) {
            isOpen = open
            drag = 0
            isDragging = false
        }
    }

    /// Проекция инерции, как у прокрутки iOS (decelerationRate 0.998).
    private static func project(_ velocity: CGFloat, rate: CGFloat = 0.998) -> CGFloat {
        (velocity / 1000) * rate / (1 - rate)
    }

    private static func rubberband(_ overshoot: CGFloat, dimension: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
        (overshoot * dimension * constant) / (dimension + constant * abs(overshoot))
    }
}

/// Горизонтальный жест панели на UIKit: системное «назад» (свайп от края и
/// во весь экран на iOS 26) ждёт, пока этот жест откажется, — поэтому
/// смахивание панели вправо не уводит из чата. Вертикаль отдаёт прокрутке.
private struct RoleChatRailPan: UIGestureRecognizerRepresentable {
    let onChange: (CGFloat) -> Void
    let onEnd: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let dx = pan.translation(in: nil).x
        switch pan.state {
        case .began, .changed: onChange(dx)
        case .ended: onEnd(dx, pan.velocity(in: nil).x)
        case .cancelled, .failed: onEnd(dx, 0)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: nil)
            return abs(v.x) > abs(v.y)
        }

        /// Системные жесты навигации ждут нас; прокрутку не держим.
        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer && !(other.view is UIScrollView)
        }
    }
}

/// Содержимое столбца: участники сверху вниз и «+» последним.
private struct RoleChatMembersColumn: View {
    let members: [RoleChatMember]
    let addable: [RoleProfile]
    let canManage: Bool
    let onMention: (RoleChatMember) -> Void
    let onAdd: (String) -> Void
    let onRemove: (RoleChatMember) -> Void

    /// Тот же рост от Dynamic Type, что у `TFAvatar` (кривая `subheadline`,
    /// база 100): иначе при уменьшенном тексте аватар ужимался, а «+» стоял
    /// на 44pt и выглядел крупнее (владелец 20.10.2026).
    @ScaledMetric(relativeTo: .subheadline) private var scalePercent: CGFloat = 100
    private var plusSide: CGFloat { (RoleChatMembersRail.avatar.rawValue * scalePercent / 100).rounded() }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TFSpacing.md) {
                ForEach(members) { member in
                    Button { onMention(member) } label: {
                        RoleMemberAvatar(member: member, size: RoleChatMembersRail.avatar)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if canManage {
                            Button(role: .destructive) { onRemove(member) } label: {
                                Label("Убрать из чата", systemImage: "person.badge.minus")
                            }
                        }
                    }
                    .accessibilityLabel("Написать: \(member.name)")
                    .accessibilityIdentifier("chat.membersRail.\(member.id)")
                }
                if canManage { addButton }
            }
            .padding(.vertical, TFSpacing.md)
            .frame(maxWidth: .infinity)
        }
    }

    private var addButton: some View {
        Menu {
            if addable.isEmpty {
                Text("Все роли уже в чате")
            } else {
                ForEach(addable) { profile in
                    Button(profile.title) { if let account = profile.accountID { onAdd(account) } }
                }
            }
        } label: {
            Image(systemName: "plus")
                .tfText(.title)
                .foregroundStyle(Color.tfSub)
                .frame(width: plusSide, height: plusSide)
                .overlay { Circle().strokeBorder(Color.tfSub, style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
        }
        .accessibilityLabel("Добавить участника")
        .accessibilityIdentifier("chat.membersRail.add")
    }
}
