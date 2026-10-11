import XCTest
@testable import TaskFlow
final class VoiceRecordingWaveformTests: XCTestCase {
    func testDecorativeTapeMovesContinuouslyAcrossBarBoundary() {
        XCTAssertEqual(VoiceRecordingWaveformView.travel(seconds: 0), 0)
        XCTAssertEqual(VoiceRecordingWaveformView.travel(seconds: 10), 180)
        XCTAssertEqual(VoiceRecordingWaveformView.travel(seconds: 0.28) - VoiceRecordingWaveformView.travel(seconds: 0.27), 0.18, accuracy: 0.00001)
        let levels = (0..<100).map { VoiceRecordingWaveformView.decorativeLevel(index: $0) }
        XCTAssertGreaterThan(Set(levels.map { Int($0 * 100) }).count, 25)
        XCTAssertGreaterThan((levels.max() ?? 0) - (levels.min() ?? 1), 0.5)
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
}
