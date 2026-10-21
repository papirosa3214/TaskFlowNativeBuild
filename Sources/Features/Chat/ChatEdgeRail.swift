import SwiftUI

/// Выезжающая панель у правой кромки (владелец 20.10.2026, по образцу
/// стороннего мессенджера). В покое — узкий край во всю высоту свободного
/// места, как закладки семьи в карточке задачи (`TaskFamilyEdgeTabs`): тот же
/// цвет листа, красноватый контур и тень. Тянется влево ровно на ширину
/// аватарки и дальше не идёт; смахнул вправо — спрятался. Системное «назад»
/// над панелью не срабатывает — см. `RoleChatRailPan`.
///
/// 21.10.2026 панель переехала из каждого чата в корень раздела «Чаты» и
/// показывает комнаты (`ChatRoomsPanel`); оболочка осталась прежней.
struct ChatEdgeRail<Content: View>: View {
    @Binding var isOpen: Bool
    let openLabel: String
    let closedLabel: String
    let identifier: String
    @ViewBuilder let content: () -> Content

    /// Живой сдвиг пальца по горизонтали (вправо — плюс), пока идёт жест.
    @State private var drag: CGFloat = 0
    @State private var isDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var width: CGFloat {
        let raw = (isOpen ? ChatEdgeRailMetrics.openWidth : ChatEdgeRailMetrics.restingWidth) - drag
        if raw > ChatEdgeRailMetrics.openWidth {
            // Дальше аватарки не идёт, но и не упирается: мягкое сопротивление.
            return ChatEdgeRailMetrics.openWidth + ChatEdgeRailMetrics.rubberband(raw - ChatEdgeRailMetrics.openWidth, dimension: ChatEdgeRailMetrics.openWidth)
        }
        return max(ChatEdgeRailMetrics.restingWidth, raw)
    }
    /// Перетяжка за упор: на сколько крат круг аватарки должен стать больше,
    /// чтобы занять расширившуюся вкладку с прежними полями. 0 в покое;
    /// возврат пружиной — вместе с шириной.
    private var stretch: CGFloat {
        let overshoot = max(0, width - ChatEdgeRailMetrics.openWidth)
        return overshoot / ChatEdgeRailMetrics.avatar.rawValue
    }
    private var reveal: CGFloat {
        min(1, (width - ChatEdgeRailMetrics.restingWidth) / ChatEdgeRailMetrics.travel)
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
                content()
                    .environment(\.chatEdgeRailStretch, stretch)
                    // Шире упора — содержимое по центру расширившейся вкладки.
                    .frame(width: max(ChatEdgeRailMetrics.openWidth, width))
                    .opacity(reveal)
                    .allowsHitTesting(isOpen && !isDragging)
            }
            .clipShape(Rectangle().inset(by: -TaskFamilyEdgeTabs.shadowRadius * 2))
            .frame(width: width)
            .frame(maxHeight: .infinity)
            // Полоса для пальца шире видимого края, чтобы край ловился;
            // у открытой — запас слева, чтобы смахнуть и не уйти «назад».
            .padding(.leading, isOpen ? ChatEdgeRailMetrics.openSlack : TaskFamilyEdgeZone.width - ChatEdgeRailMetrics.restingWidth)
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
            .accessibilityLabel(isOpen ? openLabel : closedLabel)
            .accessibilityAddTraits(isOpen ? [] : .isButton)
            .accessibilityAction { settle(open: !isOpen, velocity: 0) }
            .accessibilityIdentifier(identifier)
    }

    /// Решение по отпусканию: бросок решает направлением, медленный жест —
    /// по точке, куда панель доехала бы по инерции. Задвинуть легче, чем
    /// удержать открытой: открытая прячется, если ушла на четверть пути.
    private func finish(translation dx: CGFloat, velocity vx: CGFloat) {
        let open: Bool
        if abs(vx) > ChatEdgeRailMetrics.flickVelocity {
            open = vx < 0
        } else {
            let base = isOpen ? ChatEdgeRailMetrics.openWidth : ChatEdgeRailMetrics.restingWidth
            let projected = base - dx - ChatEdgeRailMetrics.project(vx)
            let reach = (projected - ChatEdgeRailMetrics.restingWidth) / ChatEdgeRailMetrics.travel
            open = isOpen ? reach > 0.75 : reach > 0.3
        }
        settle(open: open, velocity: vx)
    }


    /// Доезд пружиной с текущего места и со скоростью пальца — без шва
    /// между жестом и анимацией. Отскок — только после броска.
    private func settle(open: Bool, velocity vx: CGFloat) {
        let distance = (open ? ChatEdgeRailMetrics.openWidth : ChatEdgeRailMetrics.restingWidth) - width
        // Ширина растёт, когда палец идёт влево, — отсюда минус.
        let relative = abs(distance) > 0.5 ? -vx / distance : 0
        let spring: Animation = .interpolatingSpring(
            duration: 0.34, bounce: abs(vx) > ChatEdgeRailMetrics.flickVelocity ? 0.15 : 0, initialVelocity: relative)
        withAnimation(reduceMotion ? nil : spring) {
            isOpen = open
            drag = 0
            isDragging = false
        }
    }

}

/// Размеры и физика `ChatEdgeRail`: у обобщённого типа не бывает статических
/// хранимых свойств, поэтому они живут здесь.
extension EnvironmentValues {
    /// Перетяжка `ChatEdgeRail` за упор — содержимое растягивается вместе с ней.
    @Entry var chatEdgeRailStretch: CGFloat = 0
}

enum ChatEdgeRailMetrics {
    /// Ширина открытой вкладки — 44 pt и по `TFSpacing.sm` с боков; не меняется.
    static let openWidth: CGFloat = TFAvatar.Size.xl.rawValue + TFSpacing.sm * 2
    /// Аватар комнаты — во всю ширину вкладки минус по `TFSpacing.xs` с краёв
    /// (владелец 21.10.2026: «увеличить по максимуму, отступы большие»).
    static let avatar: TFAvatar.Size = .rail
    static let restingWidth = TaskFamilyEdgeTabs.restingWidth
    /// Запас для пальца левее открытой панели (владелец 20.10.2026): здесь
    /// жест забирает панель, а не системное «назад».
    static let openSlack: CGFloat = TFSpacing.lg
    static let travel = openWidth - restingWidth
    static let flickVelocity: CGFloat = 300

    /// Проекция инерции, как у прокрутки iOS (decelerationRate 0.998).
    static func project(_ velocity: CGFloat, rate: CGFloat = 0.998) -> CGFloat {
        (velocity / 1000) * rate / (1 - rate)
    }

    static func rubberband(_ overshoot: CGFloat, dimension: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
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
