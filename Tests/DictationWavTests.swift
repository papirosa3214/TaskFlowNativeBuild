import AVFoundation
import XCTest
@testable import TaskFlow

/// Упаковка записи в WAV для серверного распознавания (LOCK-DICTATION-SERVER-SOURCE-20261109).
/// Серверный ASR (`POST /asr` на `.110:1235` через `POST /api/audio/transcribe`)
/// принимает сырые байты и разбирает их ffmpeg — без корректного заголовка
/// контейнера он не понимает, где PCM, и распознавание падает.
final class DictationWavTests: XCTestCase {
    private func buffer(
        sampleRate: Double,
        samples: [Float]
    ) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
        pcm.frameLength = AVAudioFrameCount(samples.count)
        let channel = try XCTUnwrap(pcm.floatChannelData)
        for (index, value) in samples.enumerated() {
            channel[0][index] = value
        }
        return pcm
    }

    private func uint32(_ data: Data, at offset: Int) -> UInt32 {
        data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }
    }

    private func uint16(_ data: Data, at offset: Int) -> UInt16 {
        data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self) }
    }

    func testWavHeaderDescribesMono16BitPcm() throws {
        let data = try XCTUnwrap(DictationEngine.wavData(from: try buffer(sampleRate: 48000, samples: [0.5, -0.5])))

        XCTAssertEqual(data.count, 44 + 4)
        XCTAssertEqual(String(data: data.subdata(in: 0..<4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data.subdata(in: 8..<12), encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: data.subdata(in: 12..<16), encoding: .ascii), "fmt ")
        XCTAssertEqual(String(data: data.subdata(in: 36..<40), encoding: .ascii), "data")
        XCTAssertEqual(uint16(data, at: 20), 1, "PCM без сжатия")
        XCTAssertEqual(uint16(data, at: 22), 1, "моно")
        XCTAssertEqual(uint32(data, at: 24), 48000, "частота записи сохраняется как есть")
        XCTAssertEqual(uint32(data, at: 28), 96000, "байт в секунду = частота × 2")
        XCTAssertEqual(uint16(data, at: 32), 2, "байт на кадр")
        XCTAssertEqual(uint16(data, at: 34), 16, "16 бит на сэмпл")
        XCTAssertEqual(uint32(data, at: 4), 36 + 4, "RIFF-размер")
        XCTAssertEqual(uint32(data, at: 40), 4, "размер данных")
    }

    func testSamplesAreScaledToFullInt16Range() throws {
        let data = try XCTUnwrap(DictationEngine.wavData(from: try buffer(sampleRate: 16000, samples: [0.5, -0.5, 1.5, -1.5, 0])))

        let values = data.subdata(in: 44..<data.count).withUnsafeBytes { raw in
            (0..<5).map { raw.load(fromByteOffset: $0 * 2, as: Int16.self) }
        }
        XCTAssertEqual(values[0], 16384)
        XCTAssertEqual(values[1], -16384)
        XCTAssertEqual(values[2], 32767, "громче единицы обрезается, а не переворачивается")
        XCTAssertEqual(values[3], -32767)
        XCTAssertEqual(values[4], 0)
    }

    func testEmptyBufferHasNoWav() throws {
        let empty = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)),
            frameCapacity: 16
        ))
        XCTAssertNil(DictationEngine.wavData(from: empty), "пустая запись не уходит на сервер")
    }

    func testSourceNamesAreStable() {
        XCTAssertEqual(DictationEngine.Source(rawValue: "onDevice"), .onDevice)
        XCTAssertEqual(DictationEngine.Source(rawValue: "server"), .server)
        XCTAssertEqual(DictationEngine.Source.onDevice.displayName, "Телефон")
        XCTAssertEqual(DictationEngine.Source.server.displayName, "Сервер")
        XCTAssertFalse(DictationEngine.Source.server.detail.isEmpty)
    }
}
