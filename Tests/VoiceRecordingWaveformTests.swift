import XCTest
@testable import TaskFlow
final class VoiceRecordingWaveformTests: XCTestCase {
    func testAudioSamplePreservesSyllableRange() throws {
        let url = try XCTUnwrap(VoiceRecordingWaveformPreview.speechURL)
        let samples = try VoiceRecordingWaveformPreview.speechSamples(from: url)
        XCTAssertGreaterThan(samples.count, 36)
        XCTAssertGreaterThan((samples.max() ?? 0) - (samples.min() ?? 1), 0.3)
        XCTAssertGreaterThan(Set(samples.map { Int($0 * 10) }).count, 5)
        print("Speech sample: count=\(samples.count), min=\(samples.min() ?? 0), max=\(samples.max() ?? 0)")
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
