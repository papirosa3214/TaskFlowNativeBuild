import SwiftUI

/// Оформление пузыря голосового сообщения.
///
/// Цвета задаёт ВЫЗЫВАЮЩИЙ, а не этот файл: он собирается сразу в два
/// приложения — в TaskFlow и в отдельный прототип `VoiceMessageLab`, у
/// которого дизайн-системы TaskFlow нет. Значения по умолчанию — прежний
/// вид прототипа (заливка акцентом).
///
/// В чате вид сообщения не зависит от того, как его отправили (владелец
/// 21.09.2026): у своего голосового — та же красная обводка без заливки, что
/// у своего текстового. Чужое голосовое остаётся прежним пузырём прототипа,
/// как и раньше.
struct VoiceBubbleStyle {
    var fill: Color = .accentColor
    var stroke: Color?
    /// Кнопка воспроизведения: у своего сообщения заливки нет вовсе, поэтому
    /// она тоже становится обводкой.
    var playTint: Color = .accentColor
    var playFilled: Bool = true
}

/// Один пузырь для прототипа и настоящего чата.
struct VoiceMessageBubble: View {
    let message: VoiceMessage
    let player: VoicePlayer
    var style = VoiceBubbleStyle()
    @State private var showsTranscript = true

    private let cornerRadius: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button { try? player.toggle(url: message.audioURL) } label: {
                    Image(systemName: player.playingURL == message.audioURL ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 36, height: 36)
                        .background { if style.playFilled { Circle().fill(.white) } }
                        .overlay {
                            if !style.playFilled {
                                Circle().strokeBorder(style.playTint, lineWidth: 1)
                            }
                        }
                        .foregroundStyle(style.playTint)
                }
                .accessibilityLabel(player.playingURL == message.audioURL ? "Пауза" : "Воспроизвести")
                WaveformView(levels: message.waveform, color: .white).frame(height: 30)
                Text(String(format: "%d:%02d", Int(message.duration) / 60, Int(message.duration) % 60))
                    .monospacedDigit().font(.subheadline)
            }
            transcript
        }
        .padding(14)
        .foregroundStyle(.white)
        .background(style.fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if let stroke = style.stroke {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            }
        }
        .frame(maxWidth: 330, alignment: .trailing)
    }

    @ViewBuilder private var transcript: some View {
        switch message.transcript {
        case .pending:
            Label("Расшифровка…", systemImage: "waveform.badge.magnifyingglass")
                .font(.subheadline).foregroundStyle(.white.opacity(0.78))
        case .failed:
            Text("Расшифровка недоступна")
                .font(.subheadline).foregroundStyle(.white.opacity(0.78))
        case .ready(let text):
            VStack(alignment: .leading, spacing: 5) {
                Text(text)
                    .font(.body)
                    .lineLimit(showsTranscript ? nil : 2)
                    .textSelection(.enabled)
                if text.count > 120 {
                    Button(showsTranscript ? "Скрыть" : "Показать ещё") { showsTranscript.toggle() }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                }
            }
        }
    }
}

struct WaveformView: View {
    let levels: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let values = VoiceWaveform.sculptedSamples(
                from: VoiceWaveform.displaySamples(from: levels, slots: 48)
            )
            HStack(spacing: 2) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(color)
                        .frame(maxWidth: .infinity, minHeight: 2,
                               maxHeight: geometry.size.height * CGFloat(0.07 + min(0.9, level) * 0.84))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityHidden(true)
    }
}
