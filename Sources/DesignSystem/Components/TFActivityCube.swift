import SwiftUI

/// Индикатор хода агента — кубик из видео владельца (12.11.2026, IMG_9629):
/// у каждой грани своя анимация, при смене состояния кубик поворачивается на
/// нужную грань. Анимации идут только пока индикатор на экране; цвет точек —
/// текст ленты, грань — тёмная подложка поля.
enum TFActivityPhase: Int, CaseIterable, Equatable {
    /// Думает: ещё нет ни текста, ни инструментов — комета.
    case thinking
    /// Работает с инструментом — кольцо точек.
    case tool
    /// Работают роли-субагенты — четыре квадрата.
    case roles
    /// Пишет ответ — три точки.
    case writing

    var label: String {
        switch self {
        case .thinking: "Думает"
        case .tool: "Работает с инструментом"
        case .roles: "Работают роли"
        case .writing: "Пишет ответ"
        }
    }
}

struct TFActivityCube: View {
    let phase: TFActivityPhase
    var size: CGFloat = 28

    /// Сколько четвертей оборота сделал кубик: растёт на каждую смену, чтобы
    /// поворот всегда шёл в одну сторону, как в видео.
    @State private var turns = 0
    @State private var shown: TFActivityPhase

    init(phase: TFActivityPhase, size: CGFloat = 28) {
        self.phase = phase
        self.size = size
        _shown = State(initialValue: phase)
    }

    var body: some View {
        ZStack {
            face(shown)
                .rotation3DEffect(.degrees(Double(turns) * -90), axis: (x: 0, y: 1, z: 0),
                                  anchor: .center, anchorZ: -size / 2, perspective: 0.6)
        }
        .frame(width: size, height: size)
        .onChange(of: phase) { _, next in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { turns += 1 }
            // Грань меняется на середине поворота — когда она стоит ребром.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { shown = next }
        }
        .accessibilityElement()
        .accessibilityLabel(phase.label)
    }

    private func face(_ phase: TFActivityPhase) -> some View {
        RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
            .fill(Color.tfFieldDark)
            .overlay {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    Canvas { canvas, area in draw(phase, t: t, in: &canvas, area: area) }
                }
                .padding(size * 0.18)
            }
            .frame(width: size, height: size)
    }

    private func draw(_ phase: TFActivityPhase, t: TimeInterval, in canvas: inout GraphicsContext, area: CGSize) {
        let dot = Color.tfChatText
        let center = CGPoint(x: area.width / 2, y: area.height / 2)
        switch phase {
        case .thinking:
            // Комета: голова и хвост из уменьшающихся точек бегут по кругу.
            let radius = area.width * 0.36
            for i in 0..<6 {
                let angle = t * 4 - Double(i) * 0.35
                let r = area.width * (0.11 - Double(i) * 0.015)
                let p = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                canvas.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                            with: .color(dot.opacity(1 - Double(i) * 0.15)))
            }
        case .tool:
            // Кольцо из восьми точек, яркость бежит по кругу.
            let radius = area.width * 0.38
            for i in 0..<8 {
                let angle = Double(i) / 8 * 2 * .pi
                let phaseShift = (t * 1.6 - Double(i) / 8).truncatingRemainder(dividingBy: 1)
                let r = area.width * 0.07
                let p = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                canvas.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                            with: .color(dot.opacity(0.25 + 0.75 * (1 - abs(phaseShift)))))
            }
        case .roles:
            // Четыре квадрата в ряд, загораются по очереди.
            let side = area.width / 5.5
            let gap = (area.width - side * 4) / 3
            for i in 0..<4 {
                let pulse = 0.5 + 0.5 * sin(t * 6 - Double(i) * 0.9)
                let rect = CGRect(x: Double(i) * (side + gap), y: center.y - side / 2, width: side, height: side)
                canvas.fill(Path(rect), with: .color(dot.opacity(0.3 + 0.7 * pulse)))
            }
        case .writing:
            // Три точки «печатает»: подпрыгивают по очереди.
            let r = area.width * 0.09
            let gap = area.width * 0.32
            for i in 0..<3 {
                let lift = max(0, sin(t * 6 - Double(i) * 0.8)) * area.height * 0.18
                let x = center.x + Double(i - 1) * gap
                canvas.fill(Path(ellipseIn: CGRect(x: x - r, y: center.y - r - lift, width: r * 2, height: r * 2)),
                            with: .color(dot.opacity(0.55 + 0.45 * lift / max(area.height * 0.18, 1))))
            }
        }
    }
}
