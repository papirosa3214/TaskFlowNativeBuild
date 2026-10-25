import Foundation
import XCTest
@testable import TaskFlow

final class RoleChatVoiceTests: XCTestCase {
    func testRecordingMeterRespondsToFirstQuietSpeechSample() {
        let level = VoiceWaveform.recordingLevel(previous: 0, averageDecibels: -45, peakDecibels: -35)
        XCTAssertGreaterThan(level, 0.1)
        XCTAssertLessThan(level, 0.4)
    }

    func testRecordingMeterReleasesSmoothlyThroughBriefPause() {
        var level = VoiceWaveform.recordingLevel(previous: 0.8, averageDecibels: -160, peakDecibels: -160)
        XCTAssertGreaterThan(level, 0)
        XCTAssertLessThan(level, 0.4)
        for _ in 0..<19 {
            level = VoiceWaveform.recordingLevel(previous: level, averageDecibels: -160, peakDecibels: -160)
        }
        XCTAssertLessThan(level, 0.07)
    }

    func testRecordingMeterTracksSpeechPauseAndNextSyllable() {
        let first = VoiceWaveform.recordingLevel(previous: 0, averageDecibels: -40, peakDecibels: -30)
        let pause = VoiceWaveform.recordingLevel(previous: first, averageDecibels: -160, peakDecibels: -160)
        let next = VoiceWaveform.recordingLevel(previous: pause, averageDecibels: -30, peakDecibels: -20)
        XCTAssertGreaterThan(first, 0)
        XCTAssertGreaterThan(pause, 0)
        XCTAssertLessThan(pause, first * 0.8)
        XCTAssertGreaterThan(next, first)
        XCTAssertEqual(VoiceWaveform.recordingLevel(previous: 0, averageDecibels: -160, peakDecibels: -160), 0)
    }

    func testSpeechRangeKeepsOrdinaryVoiceBelowCeiling() {
        func settled(_ avg: Float, _ peak: Float) -> Double {
            var value = 0.0
            for _ in 0..<30 { value = VoiceWaveform.recordingLevel(previous: value, averageDecibels: avg, peakDecibels: peak) }
            return value
        }
        let quiet = settled(-45, -35)
        let ordinary = settled(-30, -20)
        let loud = settled(-12, -6)
        XCTAssertGreaterThan(quiet, 0.1)
        XCTAssertGreaterThan(ordinary, quiet + 0.15)
        XCTAssertLessThan(ordinary, 0.75)
        XCTAssertGreaterThan(loud, ordinary + 0.2)
        XCTAssertEqual(settled(-60, -60), 0)
        XCTAssertEqual(settled(.nan, -.infinity), 0)
    }

    func testSmoothRecordingWaveUsesAvailableWidthInsteadOfFiveBars() {
        XCTAssertEqual(
            VoiceBarsMotion.smoothBarCount(width: 180, barWidth: 3, spacing: 2),
            36
        )
        XCTAssertEqual(
            VoiceBarsMotion.smoothBarCount(width: 22, barWidth: 3, spacing: 2),
            4
        )
    }

    func testSmoothRecordingWaveRespondsToMicrophoneLevel() {
        let quiet = VoiceBarsMotion.smoothHeight(level: 0, bar: 3, count: 36, time: 0)
        let speaking = VoiceBarsMotion.smoothHeight(level: 0.8, bar: 3, count: 36, time: 0)

        XCTAssertEqual(quiet, 3, accuracy: 0.001)
        XCTAssertGreaterThan(speaking, quiet)
        XCTAssertLessThanOrEqual(speaking, 28)
    }

    func testRecordingWaveDoubleSensitivityMagnifiesQuietSpeech() {
        let baseline = VoiceBarsMotion.smoothHeight(
            level: 0.2, bar: 3, count: 36, time: 0, sensitivity: 1
        )
        let sensitive = VoiceBarsMotion.smoothHeight(
            level: 0.2, bar: 3, count: 36, time: 0, sensitivity: 2
        )

        XCTAssertGreaterThan(sensitive, baseline * 1.5)
    }

    func testChatRecordingWaveKeepsAnimatingWhenReduceMotionIsEnabled() {
        XCTAssertFalse(VoiceBarsMotion.shouldPauseTimeline(reduceMotion: true, isSmooth: true))
        XCTAssertTrue(VoiceBarsMotion.shouldPauseTimeline(reduceMotion: true, isSmooth: false))
        XCTAssertFalse(VoiceBarsMotion.shouldPauseTimeline(reduceMotion: false, isSmooth: false))
    }



    func testSmoothVoiceWaveChangesMoreGentlyWithoutChangingDefaultMotion() {
        let from = 0.3
        let to = 0.31
        let bar = 2
        let originalStep = abs(
            VoiceBarsMotion.amplitudeFactor(bar: bar, time: to, smooth: false)
                - VoiceBarsMotion.amplitudeFactor(bar: bar, time: from, smooth: false)
        )
        let smoothStep = abs(
            VoiceBarsMotion.amplitudeFactor(bar: bar, time: to, smooth: true)
                - VoiceBarsMotion.amplitudeFactor(bar: bar, time: from, smooth: true)
        )

        XCTAssertLessThan(smoothStep, originalStep)

        let originalValue = 0.72 + 0.28 * (sin(from * 7 + Double(bar) * 1.7) + 1) / 2
        XCTAssertEqual(
            VoiceBarsMotion.amplitudeFactor(bar: bar, time: from, smooth: false),
            originalValue,
            accuracy: 0.000_001
        )
    }

    func testAudioAttachmentAndTaskBindingDecode() throws {
        let decoder = JSONDecoder()
        let chat = try decoder.decode(RoleChat.self, from: Data(#"{"id":"c1","kind":"direct","created_by":"u1","task_id":"t1","members":[]}"#.utf8))
        XCTAssertEqual(chat.taskID, "t1")

        let message = try decoder.decode(RoleChatMessage.self, from: Data(#"{"id":"m1","text":"Привет","attachments":[{"id":"a1","file_name":"voice.m4a","mime":"audio/mp4","size":42}],"is_session_marker":false}"#.utf8))
        XCTAssertEqual(message.attachments?.first?.id, "a1")
        XCTAssertEqual(message.attachments?.first?.mime, "audio/mp4")
        XCTAssertEqual(message.attachments?.first?.isVoiceRecording, true)

        let currentServer = try decoder.decode(RoleChatMessage.self, from: Data(#"{"id":"m2","text":"","attachments":[{"id":"a2","file_name":"voice.m4a","mime":"application/octet-stream"}],"is_session_marker":false}"#.utf8))
        XCTAssertEqual(currentServer.attachments?.first?.isVoiceRecording, true)
    }
}
