import SwiftUI
import AVFoundation

/// Живая волна записи (владелец 14.10.2026): столбики по настоящей
/// громкости микрофона входят справа и уезжают влево, тишина и ещё не
/// записанное — ряд точек. До этого волна была декоративной — случайный
/// узор, который голос не слушал.
struct VoiceRecordingWaveformView: View {
    /// Мгновенный уровень микрофона, 0…1. Берём его, а не `waveform`
    /// рекордера: тот усреднён за 160 мс, и речь выходила ровным забором.
    let level: Double
    /// Время записи; меняется на каждом замере рекордера (раз в 40 мс).
    let elapsed: TimeInterval
    let color: Color
    let peakColor: Color
    var maxHeight: CGFloat = 28
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var history: [Double] = []
    /// Сколько замеров пришло всего: история хранит только хвост, а
    /// столбик обязан собираться из одних и тех же соседних замеров.
    @State private var received = 0
    @State private var lastLevelAt = Date()
    @State private var peak = VoiceRecordingWaveformView.quietestPeak
    // Рисунок — как у готовой волны после записи (`WaveformView`), владелец
    // 14.10.2026: та же ширина палочек, тот же зазор, те же высоты.
    private let barWidth: CGFloat = 2.5
    private let spacing: CGFloat = 2

    static let levelsPerBar = 2
    static let levelInterval: TimeInterval = 0.04
    private static let historyLimit = 400

    static func height(level: Double, maximum: Double, minimum: Double = 3) -> Double {
        minimum + min(1, max(0, level)) * max(0, maximum - minimum)
    }

    /// Высота столбика по громкости ОТНОСИТЕЛЬНО недавнего пика, а не по
    /// абсолютной шкале: микрофон телефона в режиме разговора даёт тихий
    /// сигнал, и на абсолютной шкале речь едва отрывалась от точки
    /// (владелец 14.10.2026: «хоть говори, хоть не говори — плоская»).
    /// Владелец 20.10.2026, второй заход: при 6 дБ/с и диапазоне 30 дБ речь
    /// упиралась в потолок, а в тишине сползающий пик раздувал шум микрофона
    /// (и всплеск в самом начале). Теперь: всё тише `silence` — точка при
    /// любом пике; пик не опускается ниже `quietestPeak`, спадает на 3 дБ/с;
    /// 24 дБ ниже пика — точка; лёгкий контраст степенью 1,2.
    static func normalized(level: Double, peak: Double) -> (value: Double, peak: Double) {
        let decibels = Self.decibels(level: level)
        let nextPeak = max(decibels, max(quietestPeak, peak - peakDecay))
        guard decibels > silence else { return (0, nextPeak) }
        let floor = max(nextPeak - dynamicRange, silence)
        let position = min(1, max(0, (decibels - floor) / (nextPeak - floor)))
        return (pow(position, 1.2), nextPeak)
    }

    /// Обратно из уровня рекордера (корень из линейной амплитуды между
    /// −55 и −6 дБ, см. `VoiceWaveform.recordingLevel`) в децибелы.
    static func decibels(level: Double) -> Double {
        let low = pow(10.0, -55.0 / 20)
        let high = pow(10.0, -6.0 / 20)
        let clamped = min(1, max(0, level))
        return 20 * log10(low + clamped * clamped * (high - low))
    }

    /// Ниже пик не опускается: иначе в тишине шум микрофона нормируется
    /// «в рост».
    static let quietestPeak = -30.0
    /// Абсолютный порог тишины: тише — точка при любом пике.
    static let silence = -46.0
    /// Спад пика за один замер (40 мс): 3 дБ в секунду.
    static let peakDecay = 0.12
    /// Сколько децибел ниже пика ещё рисуется столбиком, а не точкой.
    static let dynamicRange = 24.0

    /// Высота палочки — формула готовой волны: от 7 до 83 % высоты, не ниже 2 pt.
    static func barHeight(level: Double, available: Double) -> Double {
        max(2, available * (0.07 + min(0.9, max(0, level)) * 0.84))
    }

    /// Симметричное сглаживание по соседям (¼, ½, ¼): подъём и спад слога
    /// зеркальные, ровный звук держит высоту. Владелец 20.10.2026: прежняя
    /// «лепка» оставляла рост только на нарастании и срезала продолжение до
    /// 28 % — выходила резкая палка и долгий хвост.
    static func smoothed(_ bars: [Int: Double]) -> [Int: Double] {
        var result: [Int: Double] = [:]
        for (bar, value) in bars {
            let left = bars[bar - 1] ?? value
            let right = bars[bar + 1] ?? value
            result[bar] = left * 0.25 + value * 0.5 + right * 0.25
        }
        return result
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
                let bars = Self.smoothed(Self.bars(levels: history, received: received))
                // Между замерами лента едет равномерно, а не шагами.
                let sinceLevel = reduceMotion ? 0 : timeline.date.timeIntervalSince(lastLevelAt)
                let fraction = min(1, max(0, sinceLevel / Self.levelInterval))
                let progress = (Double(received) + fraction) / Double(Self.levelsPerBar)
                var bar = Int(floor(progress))
                while true {
                    let x = size.width - CGFloat(progress - Double(bar)) * pitch
                    if x < -pitch { break }
                    let level = bars[bar] ?? 0
                    let h = Self.barHeight(level: level, available: Double(size.height))
                    let rect = CGRect(x: x, y: (size.height - h) / 2, width: barWidth, height: h)
                    let tint = color.mix(with: peakColor, by: level)
                    context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(tint))
                    bar -= 1
                }
            }
        }
        .frame(height: maxHeight)
        .clipped()
        .onChange(of: elapsed) { _, _ in
            let next = Self.normalized(level: level, peak: peak)
            peak = next.peak
            history.append(next.value)
            if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
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
            VoiceRecordingWaveformView(level: samples.last ?? 0, elapsed: elapsed,
                color: .red.mix(with: .black, by: 0.55), peakColor: .red)
            Text("Расшифровка в текст")
            VoiceRecordingWaveformView(level: samples.last ?? 0, elapsed: elapsed,
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
