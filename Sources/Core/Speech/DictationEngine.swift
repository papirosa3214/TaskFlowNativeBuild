import AVFoundation
import FluidAudio
import Observation

// ═══════════ DictationEngine — распознавание речи на устройстве ═══════════
//
// Просьба владельца 03.09.2026: «подключи уже искусственный интеллект, то
// есть распознавание речи». До этого коммита `micKeyboardBar` в
// `NoteEditorScreen`/`TaskFormScreen` был чистой декорацией (`Button {}` —
// см. их комментарии) — «в проекте нигде нет живого ASR-провода на native»
// (было честно задокументировано, не мой недосмотр).
//
// Движок — NVIDIA Parakeet TDT v3 (0.6B, мультиязычный, 25 языков + русский)
// через `FluidAudio` (SPM, `argmaxinc`-соседний проект `FluidInference`,
// CoreML-порт, инференс на ANE). Владелец сам назвал эту модель — «маленькая,
// все хвалят, мультиязычная» — и явно попросил НЕ городить пикер из
// нескольких движков/размеров («не надо прям все это туда пикать это лишняя
// информация мне»): один хороший движок вместо трёх помельче нарезанных.
// WhisperKit не взят — Parakeet TDT v3 уже на голову быстрее (ANE, ~150-190x
// realtime) при сравнимом или лучшем качестве, и не тащит отдельной загрузки
// на 200МБ-1.5ГБ под каждый размер.
//
// Батч, не стриминг: жмём микрофон — пишем в буфер, отпускаем — одним
// вызовом `transcribe()` получаем готовый текст. Живых частичных результатов
// по ходу диктовки нет (FluidAudio даёт `SlidingWindowAsrManager` для этого,
// но для диктовки задачи/абзаца в заметке ждать 1-3 секунды после короткой
// фразы — не проблема, а стриминг — отдельный кусок сложности не по цели
// этой правки).
@MainActor
@Observable
public final class DictationEngine {
    public static let shared = DictationEngine()

    public enum ModelState: Equatable {
        case unknown
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    public enum RecordingState: Equatable {
        case idle
        case recording
        case transcribing
        case failed(String)
    }

    /// Какую версию Parakeet держим на телефоне. Владелец 20.09.2026:
    /// «пусть будет лёгкая и тяжёлая — двух моделей достаточно». Английскую
    /// v2 не показываем вовсе: русский она не понимает.
    public enum ModelChoice: String, CaseIterable, Identifiable, Sendable {
        case tdtCtc110m
        case v3

        public var id: String { rawValue }

        var version: AsrModelVersion {
            switch self {
            case .v3: .v3
            case .tdtCtc110m: .tdtCtc110m
            }
        }

        public var displayName: String {
            switch self {
            case .v3: "Parakeet TDT v3"
            case .tdtCtc110m: "Parakeet 110M"
            }
        }

        public var note: String {
            switch self {
            case .v3: "тяжёлая, понимает русский"
            case .tdtCtc110m: "лёгкая и быстрая"
            }
        }
    }

    /// Где распознаём запись (просьба владельца 09.11.2026: «прокинуть этот
    /// виспер мне на телефон… галочку поставь локальный, либо сервера виспер
    /// использовать чтобы я попробовал протестил»). Телефон — Parakeet на ANE,
    /// офлайн и без сети. Сервер — whisper large-v3-turbo на видеокарте `.110`
    /// через `POST /api/audio/transcribe`: аудио уходит на сервер, текст
    /// возвращается готовым (тонкий клиент, ни разбора, ни нормализации тут).
    public enum Source: String, CaseIterable, Identifiable, Sendable {
        case onDevice
        case server

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .onDevice: "Телефон"
            case .server: "Сервер"
            }
        }

        public var note: String {
            switch self {
            case .onDevice: "Parakeet, работает офлайн"
            case .server: "whisper на видеокарте .110, нужна сеть"
            }
        }

        /// Развёрнутое описание для развёрнутой строки настроек.
        public var detail: String {
            switch self {
            case .onDevice:
                "Распознаёт Parakeet TDT v3 на телефоне. Интернет не нужен, аудио с устройства не уходит."
            case .server:
                "Аудио уходит на сервер TaskFlow и распознаётся whisper large-v3-turbo на видеокарте `.110`. Нужна связь с сервером; задержка зависит от сети."
            }
        }
    }

    private static let selectedModelKey = "dictation.selectedModel"
    private static let enabledKey = "dictation.isEnabled"
    private static let sourceKey = "dictation.source"

    /// Выбранная модель переживает перезапуск: выбор владельца не должен
    /// сбрасываться к v3 при каждом входе в настройки.
    public private(set) var selectedModel: ModelChoice
    /// Диктовка на устройстве вкл/выкл. Выключена — микрофон не пишет вовсе,
    /// приложение не трогает модель (и не докачивает её втихую).
    public private(set) var isEnabled: Bool
    /// Источник распознавания переживает перезапуск — выбор владельца не
    /// должен сбрасываться к телефону при каждом входе в настройки.
    public private(set) var source: Source

    public private(set) var modelState: ModelState = .unknown
    public private(set) var recordingState: RecordingState = .idle
    /// Живой уровень громкости записи (0…1) — для анимации амплитуды у
    /// микрофона (LOCK-254, владелец 30.09.2026: «посмотри, как в чате
    /// работает голосовое, вырежи оттуда кусок, вставь сюда»). Тот же
    /// `VoiceWaveform.recordingLevel` с тем же асимметричным сглаживанием,
    /// что и запись голосового сообщения в чате — просто источник децибел
    /// другой (сырые PCM-сэмплы tap-колбэка вместо `AVAudioRecorder.meters`,
    /// у `DictationEngine` иной способ захвата микрофона).
    public private(set) var currentLevel: Double = 0

    /// Короткое сообщение о результате действия («Модель актуальна»,
    /// «Модель удалена»). Нужно потому, что кнопка без отклика выглядит
    /// мёртвой (замечание владельца 20.09.2026: «нажимаю, ничего не
    /// происходит, и мне непонятно, работает кнопка или нет»). Гаснет само.
    public private(set) var feedback: String?
    private var feedbackTask: Task<Void, Never>?

    private var asrManager: AsrManager?
    private var decoderState: TdtDecoderState?
    private let recorder = MicRecorder()

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.selectedModelKey) ?? ""
        selectedModel = ModelChoice(rawValue: raw) ?? .v3
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        let storedSource = UserDefaults.standard.string(forKey: Self.sourceKey) ?? ""
        source = Source(rawValue: storedSource) ?? .onDevice
        refreshModelState()
    }

    private func showFeedback(_ text: String) {
        feedback = text
        feedbackTask?.cancel()
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { feedback = nil }
        }
    }

    // MARK: - Настройки модели

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if !enabled { cancelRecording() }
    }

    /// Переключение источника распознавания. Запись, начатая на одном
    /// источнике, не переносится на другой: смена во время записи её отменяет.
    public func selectSource(_ newSource: Source) {
        guard newSource != source else { return }
        cancelRecording()
        source = newSource
        UserDefaults.standard.set(newSource.rawValue, forKey: Self.sourceKey)
        showFeedback("Распознавание: \(newSource.displayName.lowercased())")
    }

    /// Замена модели: сохраняем выбор, снимаем старые веса из памяти (они не
    /// подходят новому движку) и сразу качаем, если выбранной версии нет.
    public func selectModel(_ choice: ModelChoice) async {
        guard choice != selectedModel else { return }
        selectedModel = choice
        UserDefaults.standard.set(choice.rawValue, forKey: Self.selectedModelKey)
        asrManager = nil
        decoderState = nil
        refreshModelState()
        if case .notDownloaded = modelState {
            await downloadModelIfNeeded()
        }
        if case .ready = modelState {
            showFeedback("Выбрана \(choice.displayName)")
        }
    }

    /// «Проверить и обновить». FluidAudio обновления сам не сверяет, поэтому
    /// честно сообщаем по факту: весов нет — качаем; веса на месте — значит
    /// актуальны. Без сообщения кнопка выглядит нерабочей.
    public func checkModel() async {
        let hadFiles = AsrModels.modelsExist(
            at: AsrModels.defaultCacheDirectory(for: selectedModel.version),
            version: selectedModel.version
        )
        await downloadModelIfNeeded()
        switch modelState {
        case .ready: showFeedback(hadFiles ? "Модель актуальна" : "Модель скачана")
        case .failed(let message): showFeedback(message)
        default: break
        }
    }

    /// Удаление весов выбранной версии с диска. Статус пересчитывается по
    /// факту (папка), а не по флагу: прерванная загрузка флаг разъедет.
    public func deleteModel() {
        cancelRecording()
        asrManager = nil
        decoderState = nil
        let dir = AsrModels.defaultCacheDirectory(for: selectedModel.version)
        try? FileManager.default.removeItem(at: dir)
        refreshModelState()
        showFeedback("Модель удалена")
    }

    // MARK: - Модель

    /// Дешёвая проверка на диске, без сети — вызывать при открытии
    /// «Модели и голоса» и при старте приложения, чтобы честно показать
    /// «скачана»/«не скачана», не имитируя.
    public func refreshModelState() {
        guard case .downloading = modelState else {
            let dir = AsrModels.defaultCacheDirectory(for: selectedModel.version)
            modelState = AsrModels.modelsExist(at: dir, version: selectedModel.version) ? .ready : .notDownloaded
            return
        }
    }

    public func downloadModelIfNeeded() async {
        if case .ready = modelState, asrManager != nil { return }
        let version = selectedModel.version
        modelState = .downloading(0)
        do {
            let models = try await AsrModels.downloadAndLoad(
                version: version,
                progressHandler: { progress in
                    Task { @MainActor in
                        if case .downloading = DictationEngine.shared.modelState {
                            DictationEngine.shared.modelState = .downloading(progress.fractionCompleted)
                        }
                    }
                }
            )
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            asrManager = manager
            decoderState = try TdtDecoderState()
            modelState = .ready
        } catch {
            modelState = .failed(Self.message(error))
        }
    }

    // MARK: - Запись + распознавание

    /// Пуш-ту-токовый режим: жмём — пишем, ещё раз жмём (или зовём
    /// `stopRecordingAndTranscribe`) — получаем текст. Дозагружает модель
    /// сама, если она ещё не скачана (первая диктовка в жизни установки).
    public func startRecording() async {
        guard recordingState == .idle else { return }
        // Выключено в настройках — не пишем и не докачиваем модель втихую.
        guard isEnabled else {
            recordingState = .failed("Диктовка на устройстве выключена в настройках")
            return
        }
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            recordingState = .failed("Нет доступа к микрофону — разрешите в Настройках iOS")
            return
        }
        // Серверный источник модель в телефоне не трогает: ни качает, ни греет.
        // Иначе первая же серверная диктовка тянула бы веса Parakeet впустую.
        if source == .onDevice, asrManager == nil {
            await downloadModelIfNeeded()
            guard asrManager != nil else { return }
        }
        do {
            currentLevel = 0
            recorder.onLevel = { [weak self] averageDecibels, peakDecibels in
                Task { @MainActor in
                    guard let self, self.recordingState == .recording else { return }
                    self.currentLevel = VoiceWaveform.recordingLevel(
                        previous: self.currentLevel,
                        averageDecibels: averageDecibels,
                        peakDecibels: peakDecibels
                    )
                }
            }
            try recorder.start()
            recordingState = .recording
        } catch {
            recordingState = .failed(Self.message(error))
        }
    }

    /// Возвращает распознанный текст (без начальных/конечных пробелов) или
    /// `nil`, если запись была пустой/слишком короткой/распознавание упало —
    /// вызывающий код просто ничего не вставляет, без модалок с ошибкой:
    /// микрофон — необязательный ускоритель ввода, а не критичный путь.
    @discardableResult
    public func stopRecordingAndTranscribe() async -> String? {
        guard recordingState == .recording else { return nil }
        let buffer = recorder.stop()
        currentLevel = 0
        guard let buffer, buffer.frameLength > 0 else {
            recordingState = .idle
            return nil
        }
        if source == .server {
            recordingState = .transcribing
            defer { recordingState = .idle }
            let text = await transcribeOnServer(buffer)
            if let text {
                DictationLog.addEntry(engine: "server", raw: text, normalized: text)
            }
            return text
        }
        guard let asrManager, decoderState != nil else {
            recordingState = .idle
            return nil
        }
        recordingState = .transcribing
        defer { recordingState = .idle }
        do {
            var state = decoderState!
            let result = try await asrManager.transcribe(buffer, decoderState: &state, language: .russian)
            decoderState = state
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            DictationLog.addEntry(engine: "parakeet", raw: text, normalized: text)
            return text
        } catch {
            recordingState = .failed(Self.message(error))
            return nil
        }
    }

    // MARK: - Распознавание на сервере

    private struct ServerTranscript: Decodable { let text: String }

    /// Запись уходит на сервер сырыми байтами WAV и возвращается текстом.
    /// Разбора текста и нормализации здесь нет намеренно: по правилу тонкого
    /// клиента это делает сервер (см. `server/src/routes/transcribe.ts`).
    private func transcribeOnServer(_ buffer: AVAudioPCMBuffer) async -> String? {
        guard let wav = Self.wavData(from: buffer) else {
            recordingState = .failed("Не удалось подготовить запись")
            return nil
        }
        do {
            let response: ServerTranscript = try await APIClient().uploadRaw(
                path: "/audio/transcribe",
                query: [],
                data: wav,
                mime: "audio/wav"
            )
            let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            recordingState = .failed(Self.message(error))
            return nil
        }
    }

    /// PCM из буфера записи в контейнер WAV (16 бит, моно): серверный ASR
    /// принимает сырые байты и разбирает их ffmpeg — без контейнера он не
    /// поймёт, что это за звук. Частота не пересчитывается: 48 кГц с микрофона
    /// ffmpeg приводит к 16 кГц сам, дублировать ресемплинг здесь незачем.
    static func wavData(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let channels = buffer.floatChannelData else { return nil }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return nil }
        let sampleRate = UInt32(buffer.format.sampleRate)
        let sampleCount = frames
        let byteCount = sampleCount * 2

        var data = Data(capacity: 44 + byteCount)
        func append(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func append(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))            // размер блока fmt
        append(UInt16(1))             // PCM
        append(UInt16(1))             // моно
        append(sampleRate)
        append(sampleRate * 2)        // байт в секунду
        append(UInt16(2))             // байт на кадр
        append(UInt16(16))            // бит на сэмпл
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(byteCount))

        let samples = channels[0]
        var pcm = [Int16](repeating: 0, count: sampleCount)
        for index in 0..<sampleCount {
            let clamped = max(-1, min(1, samples[index]))
            pcm[index] = Int16((clamped * 32767).rounded())
        }
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }

    public func cancelRecording() {
        guard recordingState == .recording else { return }
        _ = recorder.stop()
        currentLevel = 0
        recordingState = .idle
    }

    private static func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

// MARK: - Захват микрофона в один накопительный буфер

/// Не стриминговый — копит всю диктовку в предвыделенный `AVAudioPCMBuffer`
/// на родном формате входа (без ручного ресемплинга: `AsrManager.transcribe
/// (_ audioBuffer: AVAudioPCMBuffer, ...)` сам ресемплит в 16кГц внутри —
/// свой конвертер тут был бы дублированием чужой работы).
private final class MicRecorder {
    private let engine = AVAudioEngine()
    private var buffer: AVAudioPCMBuffer?
    private var writeOffset: AVAudioFrameCount = 0
    /// (averageDecibels, peakDecibels) по последнему tap-колбэку — вызывается
    /// на аудио-потоке, не на MainActor (см. `append` ниже).
    var onLevel: ((Float, Float) -> Void)?

    /// 90с с запасом — диктовка задачи или абзаца заметки короче на порядок;
    /// хвост, который не влез, тихо не пишется (не роняем запись целиком).
    private static let maxDuration: Double = 90

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "DictationEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Микрофон недоступен"])
        }

        let capacity = AVAudioFrameCount(format.sampleRate * Self.maxDuration)
        guard let preallocated = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw NSError(domain: "DictationEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Не удалось выделить буфер записи"])
        }
        buffer = preallocated
        writeOffset = 0

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] tapBuffer, _ in
            self?.append(tapBuffer)
        }

        engine.prepare()
        try engine.start()
    }

    /// Вызывается на аудио-потоке движка (не главном) — обычный `NSLock`
    /// вместо изоляции актором, чтобы не гонять копирование через хоп на
    /// MainActor на каждый tap-колбэк (несколько раз в секунду).
    private let lock = NSLock()

    private func append(_ tapBuffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let buffer, let src = tapBuffer.floatChannelData, let dst = buffer.floatChannelData else { return }
        let remaining = buffer.frameCapacity - writeOffset
        let toCopy = min(remaining, tapBuffer.frameLength)
        guard toCopy > 0 else { return }
        for channel in 0..<Int(min(buffer.format.channelCount, tapBuffer.format.channelCount)) {
            (dst[channel] + Int(writeOffset)).update(from: src[channel], count: Int(toCopy))
        }
        writeOffset += toCopy
        reportLevel(src[0], frameCount: Int(tapBuffer.frameLength))
    }

    /// Децибелы из сырых сэмплов — тот же смысл, что `AVAudioRecorder`
    /// отдаёт готовым через `averagePower`/`peakPower`, но у `AVAudioEngine`
    /// tap такого нет, считаем сами: RMS → средняя громкость, максимум
    /// модуля сэмпла → пиковая.
    private func reportLevel(_ samples: UnsafeMutablePointer<Float>, frameCount: Int) {
        guard frameCount > 0, let onLevel else { return }
        var sumSquares: Float = 0
        var peakAmplitude: Float = 0
        for i in 0..<frameCount {
            let sample = samples[i]
            sumSquares += sample * sample
            peakAmplitude = max(peakAmplitude, abs(sample))
        }
        let rms = sqrt(sumSquares / Float(frameCount))
        let averageDecibels = 20 * log10(max(rms, 1e-7))
        let peakDecibels = 20 * log10(max(peakAmplitude, 1e-7))
        onLevel(averageDecibels, peakDecibels)
    }

    func stop() -> AVAudioPCMBuffer? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        lock.lock()
        defer { lock.unlock() }
        buffer?.frameLength = writeOffset
        let result = buffer
        buffer = nil
        writeOffset = 0
        return result
    }
}
