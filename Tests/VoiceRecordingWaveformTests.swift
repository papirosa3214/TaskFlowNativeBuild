import XCTest
@testable import TaskFlow
final class VoiceRecordingWaveformTests: XCTestCase {
    func testBarsKeepTheirLevelsWhileRecorderDropsOldOnes() {
        // Два уровня на столбик, берётся громкий.
        XCTAssertEqual(VoiceRecordingWaveformView.bars(levels: [0.2, 0.8, 0.5], received: 3), [0: 0.8, 1: 0.5])
        // Рекордер выбросил первый уровень — столбик 1 остался из тех же соседей.
        XCTAssertEqual(VoiceRecordingWaveformView.bars(levels: [0.8, 0.5, 0.1], received: 4), [0: 0.8, 1: 0.5])
        XCTAssertTrue(VoiceRecordingWaveformView.bars(levels: [], received: 0).isEmpty)
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
        XCTAssertEqual(VoiceRecordingWaveformView.height(level: 0, maximum: 28), 2)
        XCTAssertEqual(VoiceRecordingWaveformView.height(level: 1, maximum: 28), 28)
        XCTAssertLessThan(VoiceRecordingWaveformView.height(level: 0.2, maximum: 28),
                          VoiceRecordingWaveformView.height(level: 0.8, maximum: 28))
        XCTAssertEqual(VoiceRecordingWaveformView.height(level: -1, maximum: 28), 2)
        XCTAssertEqual(VoiceRecordingWaveformView.height(level: 4, maximum: 28), 28)
    }
}
