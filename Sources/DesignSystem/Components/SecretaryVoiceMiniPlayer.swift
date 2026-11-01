import SwiftUI

/// Компактное представление той же сессии: экран звонка не владеет соединением.
struct SecretaryVoiceMiniPlayer: View {
    let level: Double
    let status: String
    let isFailed: Bool
    let onExpand: () -> Void
    let onOpenChat: () -> Void
    let onEnd: () -> Void

    var body: some View {
        Button(action: onExpand) {
            SecretaryMicRing(level: level, isFailed: isFailed, micSize: 16)
                .frame(width: 64, height: 64)
                .background(Color.tfCard, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Голосовой разговор")
        .accessibilityValue(status)
        .accessibilityHint("Раскрыть разговор. В меню доступны переписка и завершение.")
        .accessibilityIdentifier("voice.mini-player")
        .hintAnchor(HintAnchorID.voiceMiniPlayer)
        .contextMenu {
            Button("Открыть переписку", systemImage: "text.bubble", action: onOpenChat)
            Button("Завершить разговор", systemImage: "phone.down", role: .destructive) {
                onEnd()
            }
        }
        .accessibilityAction(named: "Открыть переписку") { onOpenChat() }
        .accessibilityAction(named: "Завершить разговор") { onEnd() }
    }
}

/// Паттерн веб-компонента src/components/MicRing.tsx: 96 радиальных штрихов,
/// одинаковые hash-фазы, тройная волна, LERP и свечение активных кончиков.
/// level уже нормирован AudioLevelMeter; веб-усиление сырого RMS здесь не нужно.
struct SecretaryMicRing: View {
    let level: Double
    var isFailed = false
    var micSize: CGFloat = 44
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lengths = Array(repeating: 5.0, count: 96)
    @State private var inputLevel = 0.0

    private static let personalities: [(phase: Double, speed: Double, bias: Double)] =
        (0..<96).map { i in
            func fraction(_ value: Double) -> Double { value - floor(value) }
            let n = Double(i)
            return (
                fraction(sin(n * 12.9898 + 78.233) * 43758.5453) * .pi * 2,
                0.35 + fraction(sin(n * 39.346 + 11.135) * 43758.5453) * 0.95,
                0.45 + fraction(sin(n * 91.713 + 47.281) * 43758.5453) * 0.55
            )
        }

    var body: some View {
        ZStack {
            Canvas { context, size in
                let side = min(size.width, size.height)
                // На вебе canvas 360px: сохраняем пропорции на разных iPhone.
                let scale = side / 360
                let radius = side * 0.36
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0..<96 {
                    let length = reduceMotion ? 5 : lengths[i]
                    let intensity = min(1, max(0, (length - 5) / 17))
                    let angle = Double(i) / 96 * .pi * 2 - .pi / 2
                    let start = CGPoint(x: center.x + cos(angle) * radius,
                                        y: center.y + sin(angle) * radius)
                    let end = CGPoint(x: center.x + cos(angle) * (radius + length * scale),
                                      y: center.y + sin(angle) * (radius + length * scale))
                    var stroke = Path()
                    stroke.move(to: start)
                    stroke.addLine(to: end)
                    context.stroke(stroke, with: .color(Color.tfRed.opacity(0.5 + intensity * 0.5)),
                                   style: StrokeStyle(lineWidth: (2 + intensity * 1.2) * scale, lineCap: .round))
                    if intensity > 0.2 {
                        let glowRadius = (3 + intensity * 5) * scale
                        let glow = Path(ellipseIn: CGRect(x: end.x - glowRadius, y: end.y - glowRadius,
                                                         width: glowRadius * 2, height: glowRadius * 2))
                        context.fill(glow, with: .radialGradient(
                            Gradient(colors: [Color.tfRed.opacity(intensity * 0.45), Color.tfRed.opacity(0)]),
                            center: end, startRadius: 0, endRadius: glowRadius))
                    }
                }
            }
            Image(systemName: "mic")
                .tfTypeFont(size: micSize, weight: .regular)
                .foregroundStyle(Color.tfRed)
        }
        .opacity(isFailed ? 0.4 : 1)
        .accessibilityHidden(true)
        .onChange(of: level, initial: true) { _, value in inputLevel = value }
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            var previousTime = Date.timeIntervalSinceReferenceDate
            while !Task.isCancelled {
                let now = Date.timeIntervalSinceReferenceDate
                // Веб LERP=0.15 при 60fps; пересчёт сохраняет затухание при 30fps.
                let smoothing = 1 - pow(0.85, min(0.1, now - previousTime) * 60)
                previousTime = now
                let volume = inputLevel.isFinite ? min(1, max(0, inputLevel)) : 0
                var next = lengths
                for i in 0..<96 {
                    let personality = Self.personalities[i]
                    let t = now * 1.6 * personality.speed + personality.phase
                    let wave = sin(t) * 0.45 + sin(t * 2.13 + 1.7) * 0.3
                        + sin(t * 4.71 - 0.9) * 0.15 + 0.4
                    let target = 5 + volume * min(1, max(0, wave)) * personality.bias * 17
                    next[i] += (target - next[i]) * smoothing
                    if abs(next[i] - 5) < 0.01 { next[i] = 5 }
                }
                if next != lengths { lengths = next }
                // В тишине кольцо неподвижно; не перерисовываем весь экран.
                let idle = volume == 0 && next.allSatisfy { $0 == 5 }
                do { try await Task.sleep(for: .seconds(idle ? 0.1 : 1.0 / 30)) }
                catch { return }
            }
        }
    }
}
