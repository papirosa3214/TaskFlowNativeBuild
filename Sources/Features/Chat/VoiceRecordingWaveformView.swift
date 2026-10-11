import SwiftUI
import AVFoundation

/// Огибающая измерений AVAudioRecorder: столбик соответствует моменту речи.
/// Значения уже сглажены VoiceWaveform.recordingLevel, здесь нет генератора волн.
struct VoiceRecordingWaveformView: View {
    let levels: [Double]
    let elapsed: TimeInterval
    let color: Color
    let peakColor: Color
    var maxHeight: CGFloat = 28
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sampledAt = Date()
    private let barWidth: CGFloat = 3
    private let spacing: CGFloat = 2

    static func height(level: Double, maximum: Double, minimum: Double = 3) -> Double {
        minimum + min(1, max(0, level)) * max(0, maximum - minimum)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let pitch = barWidth + spacing
                let count = max(1, Int(ceil(size.width / pitch)) + 1)
                let samples = Array(levels.suffix(count))
                // За один период измерения плавно сдвигаем историю на столбик.
                let phase = reduceMotion ? 1 : min(1, max(0, timeline.date.timeIntervalSince(sampledAt) / 0.04))
                for index in 0..<count {
                    let sampleIndex = index - (count - samples.count)
                    let level = sampleIndex >= 0 ? samples[sampleIndex] : 0
                    let h = Self.height(level: level, maximum: Double(maxHeight))
                    let x = size.width - CGFloat(count - 1 - index) * pitch - barWidth + pitch * CGFloat(1 - phase)
                    let rect = CGRect(x: x, y: (size.height - h) / 2, width: barWidth, height: h)
                    let tint = color.mix(with: peakColor, by: min(1, max(0, level)))
                    context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(tint))
                }
            }
        }
        .frame(height: maxHeight)
        .clipped()
        .onChange(of: elapsed) { _, _ in sampledAt = .now }
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
        let window = max(1, Int(format.sampleRate * 0.04))
        var result: [Double] = []
        var smoothed = 0.0
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
            smoothed = VoiceWaveform.recordingLevel(previous: smoothed, averageDecibels: averageDB, peakDecibels: peakDB)
            result.append(smoothed)
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
                color: .gray, peakColor: .white, maxHeight: 30)
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
                elapsed += 0.04
                do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            }
            finished = true
        }
    }
}
#endif
