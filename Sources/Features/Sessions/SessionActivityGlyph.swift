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
    /// затем крайние вокруг стоящей середины — по полному кругу.
    private static func dots(_ c: GraphicsContext, _ a: CGSize, _ t: Double, _ s: GraphicsContext.Shading) {
        let pairs = [(0, 1), (1, 2), (0, 2)]
        let stepLength = 0.55
        let n = Int(floor(t / stepLength))
        let raw = min(1, (t / stepLength - Double(n)) / 0.8)
        let p = raw < 0.5 ? 4 * raw * raw * raw : 1 - pow(-2 * raw + 2, 3) / 2
        let r = a.width * 0.1, step = a.width * 0.28, midY = a.height / 2
        func slotX(_ i: Int) -> CGFloat { a.width / 2 + CGFloat(i - 1) * step }
        let (first, second) = pairs[n % 3]
        let center = (slotX(first) + slotX(second)) / 2
        let radius = (slotX(second) - slotX(first)) / 2
        for slot in 0..<3 {
            var x = slotX(slot), y = midY
            if slot == first || slot == second {
                let angle = (slot == first ? Double.pi : 0) + .pi * p
                x = center + radius * CGFloat(cos(angle))
                y = midY - radius * CGFloat(sin(angle))
            }
            c.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: s)
        }
    }

    /// Капля переливается по пунктиру туда-обратно и тянется на ходу.
    private static func blob(_ c: GraphicsContext, _ a: CGSize, _ t: Double, _ s: GraphicsContext.Shading) {
        let midY = a.height / 2, span = a.width * 0.4
        let phase = 2 * .pi * t * 0.6
        let x = a.width / 2 + span * sin(phase)
        let stretch = abs(cos(phase))
        let w = a.width * (0.16 + 0.22 * stretch), h = a.height * (0.2 - 0.05 * stretch)
        for i in 0..<7 {
            let dx = a.width * 0.1 + CGFloat(i) * a.width * 0.8 / 6
            guard abs(dx - x) > w / 2 + 1 else { continue }
            let r = a.width * 0.035
            c.fill(Path(ellipseIn: CGRect(x: dx - r, y: midY - r, width: r * 2, height: r * 2)), with: s)
        }
        c.fill(Path(ellipseIn: CGRect(x: x - w / 2, y: midY - h / 2, width: w, height: h)), with: s)
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
