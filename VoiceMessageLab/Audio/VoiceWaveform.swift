import Foundation

enum VoiceWaveform {
    static func microphoneLevel(averageDecibels: Float, peakDecibels: Float) -> Double {
        let speechThreshold: Float = -38
        guard averageDecibels > speechThreshold else { return 0 }

        func normalize(_ decibels: Float) -> Double {
            let progress = max(0, min(1, (decibels - speechThreshold) / 42))
            return pow(Double(progress), 0.45)
        }

        return min(1, normalize(averageDecibels) * 0.65 + normalize(peakDecibels) * 0.35)
    }

    static func displaySamples(from samples: [Double], slots: Int) -> [Double] {
        guard slots > 0 else { return [] }
        let visible = Array(samples.suffix(slots))
        return Array(repeating: 0, count: slots - visible.count) + visible
    }

    static func sculptedSamples(from samples: [Double]) -> [Double] {
        var previousRaw = 0.0
        var envelope = 0.0

        return samples.map { raw in
            let level = min(max(raw, 0), 1)
            let target: Double
            if level > previousRaw + 0.035 {
                target = level
            } else {
                target = level * 0.28
            }
            envelope += (target - envelope) * 0.72
            previousRaw = level
            return envelope
        }
    }

    static func smoothedLevel(previous: Double, raw: Double) -> Double {
        let input = min(max(raw, 0), 1)
        let response = input > previous ? 0.68 : 0.85
        return min(0.9, previous + (input - previous) * response)
    }
}
