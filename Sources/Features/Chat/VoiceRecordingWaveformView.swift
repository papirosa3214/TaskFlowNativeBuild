import SwiftUI
import AVFoundation

/// Живая волна записи (владелец 14.10.2026): тонкие столбики по настоящей
/// громкости микрофона входят справа и уезжают влево, тишина и ещё не
/// записанное — ряд точек. До этого волна была декоративной — случайный
/// узор, который голос не слушал.
struct VoiceRecordingWaveformView: View {
    /// Последние уровни рекордера, 0…1, новый — в конце; приходят раз в 40 мс.
    let levels: [Double]
    let elapsed: TimeInterval
    let color: Color
    let peakColor: Color
    var maxHeight: CGFloat = 28
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Сколько уровней пришло всего: рекордер хранит только хвост, а
    /// столбик обязан собираться из одних и тех же соседних уровней.
    @State private var received = 0
    @State private var lastLevelAt = Date()
    private let barWidth: CGFloat = 2
    private let spacing: CGFloat = 2

    static let levelsPerBar = 2
    static let levelInterval: TimeInterval = 0.04

    static func height(level: Double, maximum: Double, minimum: Double = 2) -> Double {
        minimum + min(1, max(0, level)) * max(0, maximum - minimum)
    }

    /// Столбики по сквозному номеру: каждый — самый громкий из своих
    /// `levelsPerBar` соседних уровней. `received` — номер, следующий за
    /// последним уровнем в `levels`.
    static func bars(levels: [Double], received: Int) -> [Int: Double] {
        var result: [Int: Double] = [:]
        for (offset, level) in levels.enumerated() {
            let absolute = received - levels.count + offset
            guard absolute >= 0 else { continue }
            let bar = absolute / levelsPerBar
            result[bar] = max(result[bar] ?? 0, level)
        }
        return result
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let pitch = barWidth + spacing
                let bars = Self.bars(levels: levels, received: received)
                // Между уровнями лента едет равномерно, а не шагами.
                let sinceLevel = reduceMotion ? 0 : timeline.date.timeIntervalSince(lastLevelAt)
                let fraction = min(1, max(0, sinceLevel / Self.levelInterval))
                let progress = (Double(received) + fraction) / Double(Self.levelsPerBar)
                var bar = Int(floor(progress))
                while true {
                    let x = size.width - CGFloat(progress - Double(bar)) * pitch
                    if x < -pitch { break }
                    let level = bars[bar] ?? 0
                    let h = Self.height(level: level, maximum: Double(maxHeight))
                    let rect = CGRect(x: x, y: (size.height - h) / 2, width: barWidth, height: h)
                    let tint = color.mix(with: peakColor, by: level)
                    context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(tint))
                    bar -= 1
                }
            }
        }
        .frame(height: maxHeight)
        .clipped()
        .onAppear { received = levels.count }
        .onChange(of: levels) { _, _ in
            received += 1
            lastLevelAt = .now
        }
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
