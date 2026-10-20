import XCTest
@testable import TaskFlow
final class VoiceRecordingWaveformTests: XCTestCase {
    func testBarsKeepTheirLevelsWhileRecorderDropsOldOnes() {
        // Два уровня на столбик, берётся громкий.
        XCTAssertEqual(VoiceRecordingWaveformView.bars(levels: [0.2, 0.8, 0.5], received: 3), [0: 0.8, 1: 0.5])
        // Рекордер выбросил первый уровень — столбик 1 остался из тех же соседей.
        XCTAssertEqual(VoiceRecordingWaveformView.bars(levels: [0.8, 0.5, 0.1], received: 4), [0: 0.8, 1: 0.5])
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
        // После резкого звука обычная речь через секунду снова заметна.
        var peak = VoiceRecordingWaveformView.normalized(level: 1, peak: VoiceRecordingWaveformView.quietestPeak).peak
        for _ in 0..<25 { peak = VoiceRecordingWaveformView.normalized(level: 0, peak: peak).peak }
        XCTAssertGreaterThan(VoiceRecordingWaveformView.normalized(level: 0.3, peak: peak).value, 0.3)
    }

    /// Второй заход 20.10.2026: тишина и шум микрофона — точка, речь не в потолке.
    func testSilenceIsFlatFromTheStartAndSpeechVaries() {
        let start = VoiceRecordingWaveformView.quietestPeak
        for db in [-60.0, -50.0, -47.0] {
            let level = sqrt((pow(10, db / 20) - pow(10, -55.0 / 20)) / (pow(10, -6.0 / 20) - pow(10, -55.0 / 20)))
            XCTAssertEqual(VoiceRecordingWaveformView.normalized(level: level, peak: start).value, 0, "шум \(db) дБ")
        }
        let loud = VoiceRecordingWaveformView.normalized(level: 0.6, peak: start)
        let normal = VoiceRecordingWaveformView.normalized(level: 0.3, peak: loud.peak)
        XCTAssertGreaterThan(loud.value, 0.9)
        XCTAssertGreaterThan(normal.value, 0.2)
        XCTAssertLessThan(normal.value, 0.8)
    }
}
