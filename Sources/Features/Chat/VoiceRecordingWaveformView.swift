import SwiftUI
import AVFoundation

/// Декоративная волна: непрерывная временная шкала, без переключения режимов.
struct VoiceRecordingWaveformView: View {
    let levels: [Double]
    let elapsed: TimeInterval
    let color: Color
    let peakColor: Color
    var maxHeight: CGFloat = 28
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()
    private let barWidth: CGFloat = 3
    private let spacing: CGFloat = 2

    static func height(level: Double, maximum: Double, minimum: Double = 3) -> Double {
        minimum + min(1, max(0, level)) * max(0, maximum - minimum)
    }

    static func travel(seconds: Double) -> Double { max(0, seconds) * 18 }

    private static func noise(_ index: Int) -> Double {
        let value = sin(Double(index) * 127.1 + 311.7) * 43758.5453
        return value - floor(value)
    }

    static func decorativeLevel(index: Int) -> Double {
        // Нерегулярные группы разной длины; соседние столбики тоже различаются.
        let position = Double(index) / 11
        let group = Int(floor(position))
        let fraction = position - floor(position)
        let smooth = fraction * fraction * (3 - 2 * fraction)
        let envelope = noise(group) * (1 - smooth) + noise(group + 1) * smooth
        return min(1, 0.06 + pow(envelope, 1.3) * (0.35 + noise(index + 913) * 0.65))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let pitch = barWidth + spacing
                let distance = reduceMotion ? 0 : Self.travel(seconds: timeline.date.timeIntervalSince(startedAt))
                let first = Int(floor(distance / pitch))
                let offset = CGFloat(distance.truncatingRemainder(dividingBy: Double(pitch)))
                let count = max(1, Int(ceil(size.width / pitch)) + 2)
                for slot in 0..<count {
                    let level = Self.decorativeLevel(index: first + slot)
                    let h = Self.height(level: level, maximum: Double(maxHeight))
                    let rect = CGRect(x: CGFloat(slot) * pitch - offset,
                                      y: (size.height - h) / 2, width: barWidth, height: h)
                    let tint = color.mix(with: peakColor, by: level)
                    context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(tint))
                }
            }
        }
        .frame(height: maxHeight)
        .clipped()
        .accessibilityLabel("Звуковая волна записи")
        .accessibilityIdentifier("chat.voice.recording-wave")
    }
}

#if DEBUG
/// Проверка по аудиообразцу: одна запись, без повторяющегося узора.
struct VoiceRecordingWaveformPreview: View {
    @State private var samples: [Double] = []
    @State private var elapsed = 0.0
    @State private var finished = false

    static func speechSamples(from url: URL) throws -> [Double] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        let window = max(1, Int(format.sampleRate * 0.16))
        var result: [Double] = []
        for start in stride(from: 0, to: Int(buffer.frameLength), by: window) {
            let end = min(Int(buffer.frameLength), start + window)
            var sum = 0.0
            var peak = 0.0
            for index in start..<end {
                let value = Double(channel[index])
                sum += value * value
                peak = max(peak, abs(value))
            }
            let rms = sqrt(sum / Double(end - start))
            let averageDB = Float(20 * log10(max(rms, 1e-8)))
            let peakDB = Float(20 * log10(max(peak, 1e-8)))
            result.append(VoiceWaveform.recordingBarLevel(averageDecibels: averageDB, peakDecibels: peakDB))
        }
        return result
    }

    static var speechURL: URL? {
        Bundle.main.url(forResource: "secretary-voice-kore", withExtension: "m4a")
            ?? Bundle.main.url(forResource: "secretary-voice-kore", withExtension: "m4a", subdirectory: "SecretaryVoices")
    }
    var body: some View {
        VStack(spacing: 40) {
            Text(finished ? "Аудиообразец прочитан" : "Чтение аудиообразца")
                .accessibilityIdentifier("voice.preview.ready")
            Text("Голосовое сообщение")
            VoiceRecordingWaveformView(levels: samples, elapsed: elapsed,
                color: .red.mix(with: .black, by: 0.55), peakColor: .red)
            Text("Расшифровка в текст")
            VoiceRecordingWaveformView(levels: samples, elapsed: elapsed,
                color: .red.mix(with: .black, by: 0.55), peakColor: .red, maxHeight: 30)
                .frame(width: 180)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.125))
        .foregroundStyle(.white)
        .task {
            guard let url = Self.speechURL, let fixture = try? Self.speechSamples(from: url) else { return }
            for value in fixture {
                guard !Task.isCancelled else { return }
                samples.append(value)
                if samples.count > 120 { samples.removeFirst() }
                elapsed += 0.16
                do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
            }
            finished = true
        }
    }
}
#endif
