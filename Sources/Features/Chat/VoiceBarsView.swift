import SwiftUI

/// Пять вертикальных полосок-капсул, которые «дышат» громкостью голоса
/// (владелец 26.09.2026, вариант B). Один компонент на голосовой разговор с
/// Секретарём и на запись голосового в чате — чтобы вели себя одинаково.
/// `level` — 0…1 (тот же масштаб, что `VoiceWaveform.microphoneLevel`);
/// `isWaiting` — тихое «подключаюсь»: полоски короткие, бегущая волна.
struct VoiceBarsView: View {
    var level: Double
    var color: Color
    var isWaiting = false
    var barWidth: CGFloat = 16
    var spacing: CGFloat = 10
    var maxHeight: CGFloat = 140

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Средняя выше крайних — силуэт голоса, а не ровная гребёнка.
    private static let weights: [Double] = [0.5, 0.78, 1, 0.78, 0.5]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: spacing) {
                ForEach(Self.weights.indices, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: height(bar: i, time: t))
                }
            }
            .frame(height: maxHeight)
        }
        .animation(.spring(duration: 0.18, bounce: 0.2), value: level)
        .animation(.easeInOut(duration: 0.3), value: color)
        .accessibilityHidden(true)
    }

    private func height(bar i: Int, time t: Double) -> CGFloat {
        if isWaiting {
            let wave = reduceMotion ? 0 : (sin(t * 4 - Double(i) * 0.8) + 1) / 2
            return barWidth + CGFloat(wave) * barWidth * 0.8
        }
        let jitter = reduceMotion ? 1 : 0.72 + 0.28 * (sin(t * 7 + Double(i) * 1.7) + 1) / 2
        let clamped = min(max(level, 0), 1)
        let span = maxHeight - barWidth
        return barWidth + CGFloat(clamped * Self.weights[i] * jitter) * span
    }
}
