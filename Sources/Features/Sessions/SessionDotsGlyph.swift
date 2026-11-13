import SwiftUI

// ═══ НОВАЯ ВЕРСИЯ ЧАТА: «Сессии (бета)» ═══
// Три одинаковые точки в 3D у полосы «Действия» вместо трёх плиток
// (владелец 13.11.2026, утверждено по превью). Точки в линию, промежуток —
// 1⅓ точки; по очереди восемь движений: пара верхом, пара в глубину,
// крайние вокруг середины, хоровод втроём, переворот линии в глубину, пара
// сквозь, слились-разошлись, переворот линии верхом. Линия покачивается в
// пространстве; размер у всех точек одинаковый (без перспективы); на ходу —
// смазанный хвостик. Квадратная рамка — при перевороте линия встаёт во весь
// рост и не должна обрезаться.
struct SessionDotsGlyph: View {
    var isAnimating = true
    var size: CGFloat = 18

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let radius = 0.13
    private static let spacing = radius * 2 + radius * 4 * 2 / 3
    private static let step = 0.6
    /// Полудлина линии с точкой — по ней масштаб, чтобы влезал поворот.
    private static let extent = spacing + radius

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !isAnimating)) { context in
            let t = isAnimating ? context.date.timeIntervalSinceReferenceDate : 0
            Canvas { canvas, area in
                draw(canvas, area, t)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func draw(_ c: GraphicsContext, _ a: CGSize, _ t: Double) {
        let unit = min(a.width, a.height) / 2 / Self.extent
        let center = CGPoint(x: a.width / 2, y: a.height / 2)
        let shading = GraphicsContext.Shading.color(Color.tfSub)
        let trail = isAnimating ? 8 : 0
        var points: [(SIMD3<Double>, Int)] = []
        for k in stride(from: trail, through: 0, by: -1) {
            let tk = t - Double(k) * 0.012
            for p in Self.local(tk) {
                points.append((Self.rotate(p, ax: 0.35 + 0.25 * sin(tk * 0.6), ay: 0.45 * sin(tk * 0.43)), k))
            }
        }
        points.sort { $0.0.z < $1.0.z }
        for (p, k) in points {
            var layer = c
            layer.opacity = k == 0 ? 1 : 0.35 * (1 - Double(k) / Double(max(trail, 1)))
            let r = unit * Self.radius * (1 - Double(k) / (Double(max(trail, 1)) * 2.2))
            let x = center.x + p.x * unit, y = center.y + p.y * unit
            layer.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: shading)
        }
    }

    private static func slot(_ i: Int) -> Double { Double(i - 1) * spacing }

    private static func local(_ t: Double) -> [SIMD3<Double>] {
        let n = Int(floor(t / step))
        let raw = min(1, (t / step - Double(n)) / 0.8)
        let p = raw < 0.5 ? 4 * raw * raw * raw : 1 - pow(-2 * raw + 2, 3) / 2
        switch ((n % 8) + 8) % 8 {
        case 0: return swap(0, 1, plane: 0, p)
        case 1: return swap(1, 2, plane: 2.1, p)
        case 2: return swap(0, 2, plane: 4.2, p)
        case 3: return cycle(plane: 0.8, p)
        case 4: return flip(plane: 1.57, p)
        case 5: return swap(0, 1, plane: 1.57, p)
        case 6: return merge(p)
        default: return flip(plane: 0, p)
        }
    }

    private static func swap(_ a: Int, _ b: Int, plane: Double, _ p: Double) -> [SIMD3<Double>] {
        let mid = (slot(a) + slot(b)) / 2, r = (slot(b) - slot(a)) / 2
        return (0..<3).map { s in
            guard s == a || s == b else { return SIMD3(slot(s), 0, 0) }
            let angle = (s == a ? Double.pi : 0) + .pi * p
            let o = r * sin(angle)
            return SIMD3(mid + r * cos(angle), -o * cos(plane), o * sin(plane))
        }
    }

    private static func flip(plane: Double, _ p: Double) -> [SIMD3<Double>] {
        (0..<3).map { s in
            let angle = Double.pi * p, o = slot(s) * sin(angle)
            return SIMD3(slot(s) * cos(angle), -o * cos(plane), o * sin(plane))
        }
    }

    private static func cycle(plane: Double, _ p: Double) -> [SIMD3<Double>] {
        let k = sin(Double.pi * p)
        return (0..<3).map { s in
            let angle = Double(s) * 2 * .pi / 3 + .pi / 2 + p * 2 * .pi / 3
            let line = slot(s) + (slot((s + 1) % 3) - slot(s)) * p
            return SIMD3(line * (1 - k) + spacing * cos(angle) * k,
                         -spacing * sin(angle) * k * cos(plane),
                         spacing * sin(angle) * k * sin(plane))
        }
    }

    private static func merge(_ p: Double) -> [SIMD3<Double>] {
        let k = sin(Double.pi * p)
        return (0..<3).map { SIMD3(slot($0) * (1 - k), 0, 0) }
    }

    private static func rotate(_ p: SIMD3<Double>, ax: Double, ay: Double) -> SIMD3<Double> {
        var (x, y, z) = (p.x, p.y, p.z)
        (y, z) = (y * cos(ax) - z * sin(ax), y * sin(ax) + z * cos(ax))
        (x, z) = (x * cos(ay) + z * sin(ay), -x * sin(ay) + z * cos(ay))
        return SIMD3(x, y, z)
    }
}
