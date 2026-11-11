import SwiftUI
import UIKit

enum HorizontalPanZones {
    static let defaultEdgeWidth: CGFloat = 32

    static func allowsRowSwipe(startX: CGFloat, boundsWidth: CGFloat, edgeWidth: CGFloat) -> Bool {
        guard boundsWidth > 0, edgeWidth > 0 else { return true }
        return startX <= edgeWidth || startX >= boundsWidth - edgeWidth
    }

    static func allowsPagingSwipe(
        startX: CGFloat,
        frame: CGRect,
        edgeWidth: CGFloat,
        rowIsOpen: Bool = false
    ) -> Bool {
        guard !rowIsOpen, frame.width > edgeWidth * 2 else { return false }
        return startX > frame.minX + edgeWidth && startX < frame.maxX - edgeWidth
    }
}

// ═══════════ СВАЙП СТРОКИ: перенос веб-хука useRowSwipe на UIKit ═══════════
//
// 01.09.2026, Максим: «там, где есть свайпы влево-вправо, там пиздец какой-то
// происходит… была же, ты посмотри, как в вебе было настроено, там прям
// нативный свайп был. Надо посмотреть, как это было сделано, оно было сделано
// именно с учётом прям этого iOS».
//
// Эталон — `src/lib/useRowSwipe.ts` и `src/components/TaskRow.tsx` веб-версии:
// механика вылизана на живом устройстве, все числа взяты оттуда без изменений.
//
// ═══ Почему НЕ SwiftUI DragGesture ═══
//
// В вебе жест ловится вручную на pointer-событиях: пока направление не решено,
// браузер продолжает считать движение прокруткой, и список листается. У
// SwiftUI такого промежуточного состояния нет — `DragGesture` объявляет себя
// хозяином касания ещё до первого `onChanged`, и ScrollView остаётся без
// событий. Проверено на живом телефоне во всех трёх видах: `gesture`,
// `highPriorityGesture`, `simultaneousGesture` — список не листался пальцем по
// задаче ни в одном.
//
// UIKit даёт ровно то состояние, которого не хватает: распознаватель может
// сначала посмотреть на движение и объявить себя ПРОВАЛИВШИМСЯ, если палец
// пошёл вертикально. Тогда касание достаётся `UIScrollView`, и прокрутка
// работает как обычно.
//
// ═══ Почему через `UIGestureRecognizerRepresentable`, а не своей UIView ═══
//
// Первая попытка вешала распознаватель на `superview` вьюхи из `.background` —
// касания в него не приходили вовсе (тесты: прокрутка и тап зелёные, строка не
// сдвинулась ни на пиксель). Причина: UIKit доставляет касание только
// распознавателям на hit-tested вью и её предках, а фоновая вьюха — ПОТОМОК
// хоста строки, содержимое которой SwiftUI рисует сам, без отдельных UIView.
// Тайминг привязки тут ни при чём, местоположение в дереве неисправимо.
// `UIGestureRecognizerRepresentable` (iOS 18+) — штатный мост: SwiftUI сам
// ставит распознаватель туда, куда касания доходят.

/// Кто из строк сейчас раскрыт. Нативный список держит открытой ровно одну
/// строку и закрывает её, едва начинается прокрутка; до этого раскрытых строк
/// могло накопиться сколько угодно, и список выглядел растрёпанным
/// (владелец 07.09.2026: «как-то странно»).
@MainActor
@Observable
final class TFSwipeRowRegistry {
    static let shared = TFSwipeRowRegistry()
    private(set) var openRowID: UUID?
    private var closingRowIDs: Set<UUID> = []

    var isPagingLocked: Bool { openRowID != nil || !closingRowIDs.isEmpty }

    private init() {}

    func didOpen(_ id: UUID) {
        closingRowIDs.remove(id)
        openRowID = id
    }

    func didClose(_ id: UUID) {
        if openRowID == id { openRowID = nil }
        closingRowIDs.remove(id)
    }

    /// Начали листать список — раскрытая строка закрывается.
    func closeAll() {
        if let openRowID { closingRowIDs.insert(openRowID) }
        openRowID = nil
    }
}

/// Ширина открывающейся панели действия (веб: `ROW_ACTION_W`, `ACTION_W`).
public let TFRowActionWidth: CGFloat = 84
/// Порог, после которого решается направление (веб: `DIRECTION_LOCK_PX`).
///
/// 16.09.2026: 8 → 10. Владелец на устройстве: прокрутка «очень
/// чувствительная, в начале есть сопротивление». Пока порог не пройден,
/// хозяин касания не определён и вертикальная прокрутка ещё не началась —
/// рука чувствует залипание именно в этот момент. Больший порог отдаёт
/// первые точки движения списку, а свайп строки от этого не страдает:
/// он всё равно намеренный и идёт дальше 10pt.
///
/// Верхняя граница выбрана не на глаз: эталонный touch slop в iOS —
/// 8–10 точек. Сначала поставил 12 и вышел за диапазон; 10 даёт тот же
/// выигрыш прокрутке, оставаясь в системном ощущении.
private let directionLockPx: CGFloat = 10

/// Насколько горизонталь должна преобладать (веб: `DIRECTION_BIAS`).
///
/// 16.09.2026: 1.3 → 2.0. При 1.3 горизонталь выигрывала на движении круче
/// ~38° от горизонтали, а палец при листании идёт по дуге и почти всегда
/// даёт боковую составляющую — строка перехватывала жест у списка.
/// При 2.0 горизонталью считается только явно боковое движение (круче ~27°),
/// и прокрутка выигрывает по умолчанию. Так и задумано: листают часто,
/// свайпают строку редко и осознанно.
private let directionBias: CGFloat = 2.0

/// Распознаватель, который начинается ТОЛЬКО на горизонтальном движении.
///
/// Решение принимается один раз, после порога `directionLockPx`, по формуле
/// `|dx| > |dy| × directionBias`. Вертикаль → `.failed`, и касание целиком
/// достаётся прокрутке.
///
/// Коэффициент 16.09.2026 поднят с вебовых 1.3 до 2.0 — см. `directionBias`.
final class HorizontalPanRecognizer: UIPanGestureRecognizer {
    /// Точка касания, от которой считается смещение. Именно от неё, а не от
    /// момента `began`: иначе первые 8 пикселей жеста потерялись бы и строка
    /// прыгала бы под пальцем в начале движения.
    private(set) var startLocation: CGPoint = .zero
    /// Направление уже выбрано (см. `touchesMoved`). Пока `false`, жест не
    /// мешает прокрутке; после решения в пользу горизонтали — забирает
    /// касание себе целиком.
    private(set) var decided = false
    /// 0 — свайп разрешён по всей строке. >0 — свайп разрешён только,
    /// если касание началось в пределах этой ширины от левого/правого края.
    /// Проверяется в координатах хост-вью распознавателя.
    var onlyEdgeInset: CGFloat = 0
    /// Opt-in для перелистывания планировщика; обычные свайпы строк не меняются.
    var pagingFrame: CGRect?

    func acceptsStart(localX: CGFloat, globalX: CGFloat, boundsWidth: CGFloat, rowIsOpen: Bool) -> Bool {
        if let pagingFrame {
            return HorizontalPanZones.allowsPagingSwipe(
                startX: globalX, frame: pagingFrame,
                edgeWidth: HorizontalPanZones.defaultEdgeWidth, rowIsOpen: rowIsOpen
            )
        }
        return HorizontalPanZones.allowsRowSwipe(
            startX: localX, boundsWidth: boundsWidth, edgeWidth: onlyEdgeInset
        )
    }
    func acceptsEnd(dx: CGFloat, dy: CGFloat) -> Bool {
        guard pagingFrame != nil else { return true }
        return abs(dx) >= 80 && abs(dx) > abs(dy) * 2.0
    }

    /// Прокрутка, приглушённая на время жеста, чтобы вернуть ей `isScrollEnabled`.
    private weak var lockedScrollView: UIScrollView?

    override func reset() {
        super.reset()
        decided = false
        unlockScroll()
    }

    /// Владелец 07.09.2026: «свайпаю и влево, и вниз одновременно, как-то
    /// странно». Причина — прокрутка продолжала работать параллельно уже
    /// признанному горизонтальному жесту, и палец по диагонали тянул сразу
    /// строку и список. Нативная строка так себя не ведёт: как только свайп
    /// перехвачен, список стоит. Глушим прокрутку на время жеста и включаем
    /// обратно на его конце.
    ///
    /// ⚠️ Скролл ищется ВНИЗ по иерархии, а не вверх: у
    /// `UIGestureRecognizerRepresentable` `recognizer.view` — хостинг-вью
    /// экрана, а `UIScrollView` от SwiftUI `ScrollView` его ПОТОМОК
    /// (тот же диагноз, что записан в CLAUDE.md по часовой сетке).
    private func lockScroll() {
        guard lockedScrollView == nil, let host = view else { return }
        let point = location(in: host)
        guard let scrollView = Self.verticalScrollView(in: host, containing: point) else { return }
        lockedScrollView = scrollView
        scrollView.isScrollEnabled = false
    }

    private func unlockScroll() {
        lockedScrollView?.isScrollEnabled = true
        lockedScrollView = nil
    }

    private static func verticalScrollView(in root: UIView, containing point: CGPoint) -> UIScrollView? {
        for subview in root.subviews {
            let local = root.convert(point, to: subview)
            guard subview.bounds.contains(local) else { continue }
            if let scrollView = subview as? UIScrollView,
               scrollView.contentSize.height > scrollView.bounds.height {
                return scrollView
            }
            if let found = verticalScrollView(in: subview, containing: point) {
                return found
            }
        }
        return nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        decided = false
        if let touch = touches.first {
            startLocation = touch.location(in: view)
            if let host = view,
               !acceptsStart(
                    localX: startLocation.x,
                    globalX: touch.location(in: nil).x,
                    boundsWidth: host.bounds.width,
                    rowIsOpen: TFSwipeRowRegistry.shared.isPagingLocked
               ) {
                state = .failed
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if !decided, let touch = touches.first {
            let point = touch.location(in: view)
            let dx = point.x - startLocation.x
            let dy = point.y - startLocation.y

            // Порога ещё не достигли — молчим. Ни своим, ни чужим жест пока не
            // объявляем: у прокрутки свой распознаватель, он решит сам.
            guard abs(dx) > directionLockPx || abs(dy) > directionLockPx else { return }

            decided = true
            guard abs(dx) > abs(dy) * directionBias else {
                // Вертикаль — это прокрутка, не наше дело. Раскрытую строку
                // при этом закрываем: так ведёт себя нативный список.
                state = .failed
                MainActor.assumeIsolated { TFSwipeRowRegistry.shared.closeAll() }
                return
            }
            lockScroll()
            super.touchesMoved(touches, with: event)
            // Начинаем сами, не дожидаясь, пока `UIPanGestureRecognizer`
            // дозреет до своего порога: на быстром флике (и на коротких
            // синтетических свайпах XCUITest) событий мало, и жест иначе
            // срабатывает через раз.
            if state == .possible { state = .began }
            return
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        unlockScroll()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        unlockScroll()
    }

    /// Смещение пальца по X от точки касания (веб: `ev.clientX - d.startX`).
    var horizontalTranslation: CGFloat {
        guard let view else { return 0 }
        return location(in: view).x - startLocation.x
    }

    var verticalTranslation: CGFloat {
        guard let view else { return 0 }
        return location(in: view).y - startLocation.y
    }
}

/// Горизонтальный свайп строки, не отбирающий вертикальную прокрутку.
///
/// Ставится обычным `.gesture(...)`. Логика решения — в
/// `HorizontalPanRecognizer`; сюда приходят уже готовые смещение и скорость.
struct HorizontalPan: UIGestureRecognizerRepresentable {
    /// Направление решено, жест наш (веб: `hapticCross()` в момент захвата).
    var onBegin: () -> Void = {}
    /// Смещение пальца по X за текущий жест.
    var onChange: (CGFloat) -> Void
    /// Итог жеста: смещение и скорость по X (px/с).
    var onEnd: (CGFloat, CGFloat) -> Void
    /// 0 — свайп разрешён по всей строке. >0 — свайп разрешён только в
    /// пределах этой ширины от одного из краёв строки.
    var onlyEdgeInset: CGFloat = 0
    /// Перелистывание принимает жест только внутри ленты и отменяет тап задачи.
    var pagingFrame: CGRect? = nil

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> HorizontalPanRecognizer {
        let recognizer = makeRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func makeRecognizer() -> HorizontalPanRecognizer {
        let recognizer = HorizontalPanRecognizer()
        recognizer.onlyEdgeInset = onlyEdgeInset
        recognizer.pagingFrame = pagingFrame
        if pagingFrame != nil { recognizer.cancelsTouchesInView = true }
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: HorizontalPanRecognizer, context: Context) {
        // Геометрия появляется после первого layout; не фиксируем начальный .zero.
        recognizer.pagingFrame = pagingFrame
    }

    func handleUIGestureRecognizerAction(_ recognizer: HorizontalPanRecognizer, context: Context) {
        switch recognizer.state {
        case .began:
            onBegin()
            onChange(recognizer.horizontalTranslation)
        case .changed:
            onChange(recognizer.horizontalTranslation)
        case .ended:
            guard recognizer.acceptsEnd(dx: recognizer.horizontalTranslation, dy: recognizer.verticalTranslation) else { return }
            onEnd(recognizer.horizontalTranslation, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed:
            // Отменённое касание не перелистывает раздел. Свайпы строк сохраняют доводку.
            guard pagingFrame == nil else { return }
            onEnd(recognizer.horizontalTranslation, recognizer.velocity(in: recognizer.view).x)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Пока направление не выбрано — не мешаем никому: прокрутка должна
        /// иметь возможность начаться сама, иначе список не листается пальцем
        /// по строке. После решения в пользу горизонтали одновременность
        /// запрещена, иначе диагональный палец тянет строку и список разом.
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            guard let pan = g as? HorizontalPanRecognizer else { return true }
            return !pan.decided
        }
    }
}
