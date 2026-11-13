import SwiftUI

// ═══ НОВАЯ ВЕРСИЯ ЧАТА: «Сессии (бета)» ═══
// Значок хода вместо кубика (владелец 13.11.2026, видео IMG_9629: «смотри не на
// кубик, а на иконку в центре… вот такие четыре иконки точь-в-точь»).
// Четыре анимации с граней кубика, каждая — своему состоянию хода:
// пишет — три точки меняются местами по кругу; думает — капля по пунктиру; инструмент — кольцо
// из восьми точек с бегущей волной; роли — четыре квадратика лесенкой.
struct SessionActivityGlyph: View {
    let phase: TFActivityPhase
    var size: CGFloat = 22

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, area in
                let color = GraphicsContext.Shading.color(Color.tfSub)
                switch phase {
                case .writing: Self.dots(canvas, area, t, color)
                case .thinking: Self.blob(canvas, area, t, color)
                case .tool: Self.ring(canvas, area, t, color)
                case .roles: Self.squares(canvas, area, t, color)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(phase.label)
    }

    /// Три точки меняются местами по окружности (видео владельца, 13.11.2026:
    /// «не прыгают… местами меняются по кругу»): левая пара, правая пара,
    /// затем крайние вокруг стоящей середины — по полному кругу. Между точками
    /// воздух, на ходу — смазанный хвостик (владелец 13.11.2026).
    private static func dots(_ c: GraphicsContext, _ a: CGSize, _ t: Double, _ s: GraphicsContext.Shading) {
        let r = a.width * 0.1
        let trail = 8
        for k in stride(from: trail, through: 0, by: -1) {
            var layer = c
            layer.opacity = k == 0 ? 1 : 0.35 * (1 - Double(k) / Double(trail))
            let rr = r * CGFloat(1 - Double(k) / (Double(trail) * 2.2))
            for point in dotPositions(a, t - Double(k) * 0.012) {
                layer.fill(Path(ellipseIn: CGRect(x: point.x - rr, y: point.y - rr, width: rr * 2, height: rr * 2)), with: s)
            }
        }
    }

    private static func dotPositions(_ a: CGSize, _ t: Double) -> [CGPoint] {
        let pairs = [(0, 1), (1, 2), (0, 2)]
        let stepLength = 0.55
        let n = Int(floor(t / stepLength))
        let raw = min(1, (t / stepLength - Double(n)) / 0.8)
        let p = raw < 0.5 ? 4 * raw * raw * raw : 1 - pow(-2 * raw + 2, 3) / 2
        let step = a.width * 0.34, midY = a.height / 2
        func slotX(_ i: Int) -> CGFloat { a.width / 2 + CGFloat(i - 1) * step }
        let (first, second) = pairs[((n % 3) + 3) % 3]
        let center = (slotX(first) + slotX(second)) / 2
        let radius = (slotX(second) - slotX(first)) / 2
        return (0..<3).map { slot in
            guard slot == first || slot == second else { return CGPoint(x: slotX(slot), y: midY) }
            let angle = (slot == first ? Double.pi : 0) + .pi * p
            return CGPoint(x: center + radius * CGFloat(cos(angle)), y: midY - radius * CGFloat(sin(angle)))
        }
    }

    /// Ряд маленьких точек; толстая капля справа четыре раза выстреливает
    /// каплю с хвостиком — та бежит влево и у края исчезает, следом стартует
    /// новая; капля справа худеет, потом остаются только точки (владелец
    /// 13.11.2026, по превью: «наконец-то… точечки пожирнее, хвостик длиннее»).
    private static func blob(_ c: GraphicsContext, _ a: CGSize, _ t: Double, _ s: GraphicsContext.Shading) {
        let count = 7, shots = 4, travel = 0.5, rest = 0.6
        let cycle = Double(shots) * travel + rest
        let local = t.truncatingRemainder(dividingBy: cycle)
        let midY = a.height / 2, x0 = a.width * 0.06, x1 = a.width * 0.94
        let small = a.width * 0.042, big = a.width * 0.075
        func dot(_ ctx: GraphicsContext, _ x: CGFloat, _ r: CGFloat) {
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: midY - r, width: r * 2, height: r * 2)), with: s)
        }
        for i in 0..<count { dot(c, x0 + (x1 - x0) * CGFloat(i) / CGFloat(count - 1), small) }
        let shot = Int(local / travel)
        let fired = min(shots, shot + (local < Double(shots) * travel ? 1 : 0))
        let left = max(0, shots - fired)
        if left > 0 { dot(c, x1, small + (big * 1.3 - small) * CGFloat(left) / CGFloat(shots)) }
        guard shot < shots else { return }
        let progress = (local - Double(shot) * travel) / travel
        let eased = 1 - pow(1 - progress, 2)
        let x = x1 - (x1 - x0) * CGFloat(eased)
        let tail = 14
        for k in stride(from: tail, through: 0, by: -1) {
            let xs = x + (x1 - x0) * 0.035 * CGFloat(k) * CGFloat(1 - eased * 0.3)
            guard xs <= x1 else { continue }
            var layer = c
            layer.opacity = k == 0 ? 1 : 0.4 * (1 - Double(k) / Double(tail))
            dot(layer, xs, big * CGFloat(1 - Double(k) / Double(tail + 6)))
        }
    }

    /// Восемь точек по кругу; волна обегает кольцо, точки на ней разбухают.
    private static func ring(_ c: GraphicsContext, _ a: CGSize, _ t: Double, _ s: GraphicsContext.Shading) {
        let center = CGPoint(x: a.width / 2, y: a.height / 2), radius = a.width * 0.36
        let head = 2 * .pi * t * 0.8
        for i in 0..<8 {
            let angle = Double(i) / 8 * 2 * .pi
            let bump = pow(max(0, cos(angle - head)), 4)
            let r = a.width * (0.04 + 0.06 * bump)
            let p = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            c.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: s)
        }
    }

    /// Четыре квадратика в ряд поднимаются лесенкой и опускаются.
    private static func squares(_ c: GraphicsContext, _ a: CGSize, _ t: Double, _ s: GraphicsContext.Shading) {
        let side = a.width * 0.16, gap = a.width * 0.06
        let total = side * 4 + gap * 3, left = (a.width - total) / 2
        let baseY = a.height * 0.62
        for i in 0..<4 {
            let lift = max(0, sin(2 * .pi * t * 0.7 - Double(i) * 0.5)) * a.height * 0.3
            let rect = CGRect(x: left + CGFloat(i) * (side + gap), y: baseY - side - lift, width: side, height: side + lift * 0.4)
            c.fill(Path(rect), with: s)
        }
    }
}
