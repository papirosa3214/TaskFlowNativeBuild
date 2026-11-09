import Foundation
import CoreGraphics

/// Геометрия ленты чата: где лента сейчас и идёт ли она за низом.
///
/// Правила вынесены из экрана чистой структурой: раньше они жили в
/// модификаторах SwiftUI (`defaultScrollAnchor`, чтение геометрии в замыканиях),
/// и проверить их без телефона было нечем. Лента на нативной коллекции получает
/// замеры из `UIScrollView`, а решения принимаются здесь — и проверяются
/// целевым тестом на хосте (`Tools/test_chat_feed_scroll_policy.py`).
enum ChatFeedScrollPolicy {
    /// Насколько близко к низу лента считается «у низа».
    static let nearBottomDistance: CGFloat = 80
    /// Насколько близко к верху лента дорисовывает старые сообщения.
    static let nearTopDistance: CGFloat = 300

    struct Position: Equatable {
        var isNearBottom: Bool
        var isNearTop: Bool
        var distanceToBottom: CGFloat
    }

    /// Где лента по её геометрии.
    /// - Parameters:
    ///   - contentHeight: высота содержимого.
    ///   - offset: смещение прокрутки (как отдаёт `UIScrollView.contentOffset.y`).
    ///   - viewport: высота видимой области.
    ///   - insetTop: верхний отступ содержимого.
    ///   - insetBottom: нижний отступ содержимого.
    static func position(contentHeight: CGFloat, offset: CGFloat, viewport: CGFloat,
                         insetTop: CGFloat = 0, insetBottom: CGFloat = 0) -> Position {
        let distanceToBottom = contentHeight + insetBottom - (offset + viewport)
        let distanceToTop = offset + insetTop
        return Position(isNearBottom: distanceToBottom <= nearBottomDistance,
                        isNearTop: distanceToTop <= nearTopDistance,
                        distanceToBottom: distanceToBottom)
    }

    /// Меняется ли привязка к низу. Двигает её только рука владельца: рост
    /// ответа тоже меняет геометрию, и «на миг не у низа» — не повод отпустить
    /// низ (владелец 30.10.2026).
    static func followsBottom(current: Bool, isNearBottom: Bool, byUser: Bool) -> Bool {
        byUser ? isNearBottom : current
    }

    /// Смещение, при котором лента стоит у низа.
    static func bottomOffset(contentHeight: CGFloat, viewport: CGFloat,
                             insetTop: CGFloat, insetBottom: CGFloat) -> CGFloat {
        max(-insetTop, contentHeight - viewport + insetBottom)
    }
}
