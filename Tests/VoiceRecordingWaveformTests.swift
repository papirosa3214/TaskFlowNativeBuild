import XCTest
@testable import TaskFlow
final class VoiceRecordingWaveformTests: XCTestCase {
    func testBarsKeepTheirLevelsWhileRecorderDropsOldOnes() {
        // Три уровня на столбик, берётся громкий (20.10.2026: «3 замера по
        // 40 мс = столбик раз в 120 мс»).
        XCTAssertEqual(VoiceRecordingWaveformView.bars(levels: [0.2, 0.8, 0.5, 0.6], received: 4), [0: 0.8, 1: 0.6])
        // Рекордер выбросил первый уровень — столбик 1 остался из тех же соседей.
        XCTAssertEqual(VoiceRecordingWaveformView.bars(levels: [0.8, 0.5, 0.1, 0.4], received: 5), [0: 0.8, 1: 0.4])
        XCTAssertTrue(VoiceRecordingWaveformView.bars(levels: [], received: 0).isEmpty)
        // Пауза между слогами падает к точке, громкий слог — в полный рост.
        // Тихая речь (около −40 дБ) встаёт в рост, тишина остаётся точкой.
        let quietSpeech = 0.13
        XCTAssertEqual(VoiceRecordingWaveformView.decibels(level: quietSpeech), -40, accuracy: 1.5)
        let speech = VoiceRecordingWaveformView.normalized(level: quietSpeech, peak: VoiceRecordingWaveformView.quietestPeak)
        XCTAssertGreaterThan(speech.value, 0.9)
        XCTAssertEqual(VoiceRecordingWaveformView.normalized(level: 0, peak: speech.peak).value, 0)
        // Слог на 10 дБ тише пика заметно ниже, но не точка.
        let softer = VoiceRecordingWaveformView.normalized(level: 0.3, peak: -20)
        XCTAssertGreaterThan(softer.value, 0.2)
        XCTAssertLessThan(softer.value, 0.8)
    }
    func testAudioSamplePreservesSyllableRange() throws {
        let url = try XCTUnwrap(VoiceRecordingWaveformPreview.speechURL)
        let samples = try VoiceRecordingWaveformPreview.speechSamples(from: url)
        XCTAssertGreaterThan(samples.count, 15)
        XCTAssertGreaterThan((samples.max() ?? 0) - (samples.min() ?? 1), 0.3)
        XCTAssertGreaterThan(Set(samples.map { Int($0 * 10) }).count, 5)
        print("Speech sample: count=\(samples.count), min=\(samples.min() ?? 0), max=\(samples.max() ?? 0)")
    }
    func testEachBarHasItsOwnLevelWithoutReleaseTail() {
        let loud = VoiceWaveform.recordingBarLevel(averageDecibels: -12, peakDecibels: -6)
        let quiet = VoiceWaveform.recordingBarLevel(averageDecibels: -45, peakDecibels: -35)
        let normal = VoiceWaveform.recordingBarLevel(averageDecibels: -30, peakDecibels: -20)
        XCTAssertGreaterThan(loud, normal)
        XCTAssertGreaterThan(normal, quiet)
        XCTAssertGreaterThan(quiet, 0.15)
        XCTAssertEqual(VoiceWaveform.recordingBarLevel(averageDecibels: -80, peakDecibels: -70), 0)
    }
    func testSilenceStaysFlatAndSpeechRetainsAmplitude() {
        XCTAssertEqual(VoiceRecordingWaveformView.height(level: 0, maximum: 28), 3)
        XCTAssertEqual(VoiceRecordingWaveformView.height(level: 1, maximum: 28), 28)
        XCTAssertLessThan(VoiceRecordingWaveformView.height(level: 0.2, maximum: 28),
                          VoiceRecordingWaveformView.height(level: 0.8, maximum: 28))
        XCTAssertEqual(VoiceRecordingWaveformView.height(level: -1, maximum: 28), 3)
        XCTAssertEqual(VoiceRecordingWaveformView.height(level: 4, maximum: 28), 28)
    }

    /// Владелец 20.10.2026: подъём и спад слога — зеркальные, ровный звук не срезается.
    func testLiveWaveIsSymmetricAndHoldsSustainedSound() {
        let syllable = VoiceRecordingWaveformView.smoothed([0: 0, 1: 0, 2: 1, 3: 0, 4: 0])
        XCTAssertEqual(syllable[1] ?? 0, syllable[3] ?? 0, accuracy: 1e-9)
        XCTAssertGreaterThan(syllable[2] ?? 0, syllable[1] ?? 0)
        let sustained = VoiceRecordingWaveformView.smoothed([0: 0.8, 1: 0.8, 2: 0.8, 3: 0.8])
        XCTAssertEqual(sustained[2] ?? 0, 0.8, accuracy: 1e-9)
        // После резкого звука обычная речь снова заметна. Живая волна
        // нормируется по самому громкому месту записи (`normalizedHistory`),
        // а не по остывающему пику: речь после громкого слога остаётся
        // столбиком, а не точкой (пороги 20.10.2026).
        let loud = VoiceRecordingWaveformView.amplitude(level: 0.9)
        let speech = VoiceRecordingWaveformView.amplitude(level: 0.088)
        let history = VoiceRecordingWaveformView.normalizedHistory([loud, 0, speech])
        XCTAssertEqual(history[0], 1, accuracy: 0.0001, "громкий слог — потолок записи")
        XCTAssertEqual(history[1], 0, "тишина — точка")
        XCTAssertGreaterThan(history[2], 0.15, "обычная речь после громкого звука снова заметна")
        // И столбик этой речи — не точка: рисунок умножает голос, но не обнуляет.
        XCTAssertGreaterThan(VoiceRecordingWaveformView.patterned(voice: history[2], bar: 0), 0.05)
    }

    /// Второй заход 20.10.2026: тишина и шум микрофона — точка, речь не в потолке.
    func testSilenceIsFlatFromTheStartAndSpeechVaries() {
        let start = VoiceRecordingWaveformView.quietestPeak
        // Паузы владельца (−75…−80 дБ) рекордер отдаёт как нижний уровень — точка.
        XCTAssertEqual(VoiceRecordingWaveformView.normalized(level: 0, peak: start).value, 0)
        let loud = VoiceRecordingWaveformView.normalized(level: 0.6, peak: start)
        let normal = VoiceRecordingWaveformView.normalized(level: 0.3, peak: loud.peak)
        XCTAssertGreaterThan(loud.value, 0.9)
        XCTAssertGreaterThan(normal.value, 0.2)
        XCTAssertLessThan(normal.value, 0.8)
    }
}
