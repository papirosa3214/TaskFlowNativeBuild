import XCTest
@testable import TaskFlow
final class VoiceRecordingWaveformTests: XCTestCase {
    func testSilenceStaysFlatAndSpeechRetainsAmplitude() {
        XCTAssertEqual(VoiceRecordingWaveformView.height(level: 0, maximum: 28), 3)
        XCTAssertEqual(VoiceRecordingWaveformView.height(level: 1, maximum: 28), 28)
        XCTAssertLessThan(VoiceRecordingWaveformView.height(level: 0.2, maximum: 28),
                          VoiceRecordingWaveformView.height(level: 0.8, maximum: 28))
        XCTAssertEqual(VoiceRecordingWaveformView.height(level: -1, maximum: 28), 3)
        XCTAssertEqual(VoiceRecordingWaveformView.height(level: 4, maximum: 28), 28)
    }
}
