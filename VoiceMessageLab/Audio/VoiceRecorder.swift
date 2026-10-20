import AVFoundation
import Foundation
import Observation
import os

struct RecordedVoice: Equatable {
    let url: URL
    let duration: TimeInterval
    let waveform: [Double]
}

@MainActor
protocol VoiceRecording: AnyObject {
    var state: VoiceRecorder.State { get }
    func start() async throws
    func finish() throws -> RecordedVoice?
    func cancel()
}

@MainActor
@Observable
final class VoiceRecorder: VoiceRecording {
    enum State: Equatable {
        case idle
        case recording(elapsed: TimeInterval, level: Double)
        case failed(String)
    }

    private(set) var state: State = .idle
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var meterTask: Task<Void, Never>?
    private(set) var waveform: [Double] = []
    private var smoothedLevel = 0.0
    /// Прямой замер микрофона (владелец 20.10.2026): системный измеритель
    /// `averagePower` усредняет ~0,3 с — речь выходила ровным забором, после
    /// паузы тянулся хвост. Пик каждого куска звука копится здесь до замера.
    private var meterEngine: AVAudioEngine?
    private let tapPeak = OSAllocatedUnfairLock<Float?>(initialState: nil)

    func start() async throws {
        guard case .idle = state else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .failed("Нет доступа к микрофону")
            return
        }

        let session = AVAudioSession.sharedInstance()
        // .default, а не .voiceChat: режим звонков включает автоусиление, и оно
        // выравнивает громкость голоса — волна без амплитуды (20.10.2026).
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let directory = try Self.recordingsDirectory()
        let url = directory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let audioRecorder = try AVAudioRecorder(
            url: url,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
        )
        audioRecorder.isMeteringEnabled = true
        guard audioRecorder.record() else {
            throw NSError(domain: "VoiceRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не удалось начать запись"])
        }
        recorder = audioRecorder
        recordingURL = url
        waveform = []
        smoothedLevel = 0
        state = .recording(elapsed: 0, level: 0)
        startDirectMeter()
        startMetering()
    }

    func finish() throws -> RecordedVoice? {
        guard let recorder, let recordingURL else { return nil }
        let duration = recorder.currentTime
        stopRecorder()
        return RecordedVoice(url: recordingURL, duration: duration, waveform: waveform)
    }

    func cancel() {
        let url = recordingURL
        stopRecorder()
        if let url { try? Self.cancelRecordingFile(at: url) }
    }

    static func cancelRecordingFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func stopRecorder() {
        meterTask?.cancel()
        meterTask = nil
        meterEngine?.inputNode.removeTap(onBus: 0)
        meterEngine?.stop()
        meterEngine = nil
        tapPeak.withLock { $0 = nil }
        recorder?.stop()
        recorder = nil
        recordingURL = nil
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Пик модуля сэмплов каждого буфера (~20 мс) — без усреднения. Не
    /// запустился — остаётся системный измеритель, запись не страдает.
    private func startDirectMeter() {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        let box = tapPeak
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            var peak: Float = 0
            for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(channel[i])) }
            let db = 20 * log10(max(peak, 1e-7))
            box.withLock { $0 = max($0 ?? -160, db) }
        }
        do {
            try engine.start()
            meterEngine = engine
        } catch {
            input.removeTap(onBus: 0)
        }
    }

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { @MainActor in
            var power = 0.0
            var peak: Float = -160
            var readings = 0
            while !Task.isCancelled, let recorder {
                recorder.updateMeters()
                // Каждый замер сам по себе, без смешивания с прошлым: иначе
                // столбик волны тянул за собой хвост (владелец 20.10.2026).
                if meterEngine != nil, let direct = tapPeak.withLock({ value -> Float? in
                    defer { value = nil }
                    return value
                }) {
                    smoothedLevel = VoiceWaveform.instantLevel(averageDecibels: direct, peakDecibels: direct)
                } else if meterEngine == nil {
                    smoothedLevel = VoiceWaveform.instantLevel(
                        averageDecibels: recorder.averagePower(forChannel: 0),
                        peakDecibels: recorder.peakPower(forChannel: 0)
                    )
                } else {
                    smoothedLevel = 0
                }
                power += pow(10, Double(recorder.averagePower(forChannel: 0)) / 10)
                peak = max(peak, recorder.peakPower(forChannel: 0))
                readings += 1
                if readings == 4 {
                    waveform.append(VoiceWaveform.recordingBarLevel(
                        averageDecibels: Float(10 * log10(max(power / 4, 1e-16))),
                        peakDecibels: peak
                    ))
                    if waveform.count > 120 { waveform.removeFirst(waveform.count - 120) }
                    power = 0
                    peak = -160
                    readings = 0
                }
                state = .recording(elapsed: recorder.currentTime, level: smoothedLevel)
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }

    private static func recordingsDirectory() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("VoiceMessageLab/Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
