import Foundation

/// Геометрия возврата без SwiftUI: порты на окружности, наконечник по касательной.
enum PlanReturnGeometry {
    struct Route {
        let start, control1, control2, end: CGPoint
        let headLeft, headRight: CGPoint
    }

    static func route(from source: CGPoint, to target: CGPoint, radius: CGFloat, width: CGFloat) -> Route {
        let start, end, control1, control2: CGPoint
        if abs(target.x - source.x) > abs(target.y - source.y) {
            let direction: CGFloat = target.x >= source.x ? 1 : -1
            start = CGPoint(x: source.x + direction * radius, y: source.y)
            end = CGPoint(x: target.x - direction * radius, y: target.y)
            let control = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - 10)
            // Та же малая квадратичная дуга, представленная кубической.
            control1 = CGPoint(x: start.x + (control.x - start.x) * 2 / 3,
                               y: start.y + (control.y - start.y) * 2 / 3)
            control2 = CGPoint(x: end.x + (control.x - end.x) * 2 / 3,
                               y: end.y + (control.y - end.y) * 2 / 3)
        } else {
            let leftSpace = min(source.x, target.x) - radius - 8
            let rightSpace = width - max(source.x, target.x) - radius - 8
            let side: CGFloat = leftSpace >= radius || leftSpace >= rightSpace ? -1 : 1
            start = CGPoint(x: source.x + side * radius, y: source.y)
            end = CGPoint(x: target.x + side * radius, y: target.y)
            let space = max(0, side < 0 ? leftSpace : rightSpace)
            let bend = min(radius, space)
            let outside = side < 0 ? min(start.x, end.x) - bend : max(start.x, end.x) + bend
            control1 = CGPoint(x: outside, y: start.y)
            control2 = CGPoint(x: outside, y: end.y)
        }
        let length = max(0.001, hypot(end.x - control2.x, end.y - control2.y))
        let ux = (end.x - control2.x) / length, uy = (end.y - control2.y) / length
        return Route(start: start, control1: control1, control2: control2, end: end,
                     headLeft: CGPoint(x: end.x - ux * 5 - uy * 4, y: end.y - uy * 5 + ux * 4),
                     headRight: CGPoint(x: end.x - ux * 5 + uy * 4, y: end.y - uy * 5 - ux * 4))
    }
}
