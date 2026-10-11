import SwiftUI
import Testing

@testable import TaskFlow

/// Регрессия на жалобу владельца: больше половины жеста карта «ватала», а под
/// самый конец разом становилась объёмной. Причина — кубический easing камеры и
/// ease-out роста столбиков, из-за которых вся трансформация сваливалась в
/// середину пути.
struct HeatmapExpansionTests {

    private func steps(_ curve: (CGFloat) -> CGFloat, samples: Int = 200) -> [CGFloat] {
        (0..<samples).map { i in
            curve(CGFloat(i + 1) / CGFloat(samples)) - curve(CGFloat(i) / CGFloat(samples))
        }
    }

    @Test("Камера раскрывается равномерно на всём пути, без провала и без рывка")
    func cameraProgressIsEven() {
        let deltas = steps { HeatmapExpansion.cameraEase($0) }
        let mean = deltas.reduce(0, +) / CGFloat(deltas.count)

        #expect(deltas.min()! > mean * 0.5,
                "в начале жеста трансформация почти не идёт — карта «ватает»")
        #expect(deltas.max()! < mean * 1.5,
                "в конце жеста трансформация рвётся — карта разом становится объёмной")

        // Разброс шага по всему пути: кубический in-out давал здесь ~1800x.
        let spread = deltas.max()! / deltas.min()!
        #expect(spread < 1.6, "разброс скорости по пути \(spread)x — раскатка неравномерна")
    }

    @Test("Карта уже наклонена в первой четверти жеста, а не вращается плоской")
    func planeTiltsBeforeHalfway() {
        let finalAngle = CGFloat.pi * 56 / 180
        // Ratio of projected plane depth to its un-tilted depth; the old shared
        // camera curve retained ~97% at a quarter and ~88% halfway.
        #expect(cos(finalAngle * HeatmapExpansion.tiltProgress(0.25)) < 0.94)
        #expect(cos(finalAngle * HeatmapExpansion.tiltProgress(0.5)) < 0.78)
        #expect(HeatmapExpansion.tiltProgress(0) == 0)
        #expect(abs(HeatmapExpansion.tiltProgress(1) - 1) < 0.0001)
        #expect(HeatmapExpansion.tiltProgress(-1) == 0)
        #expect(abs(HeatmapExpansion.tiltProgress(2) - 1) < 0.0001)
    }

    @Test("Столбики растут линейно, а не взлетают ease-out в начале")
    func columnsRiseLinearly() {
        let deltas = steps { HeatmapExpansion.rise($0) }
        #expect(deltas.max()! - deltas.min()! < 0.0001,
                "рост столбиков неравномерен — последние колонки догоняют у самого финиша")
    }

    @Test("Крайние значения зажаты: жест глубже экрана не ломает геометрию")
    func curveStaysInRange() {
        #expect(HeatmapExpansion.cameraEase(-1) == 0)
        #expect(HeatmapExpansion.cameraEase(0) == 0)
        #expect(abs(HeatmapExpansion.cameraEase(1) - 1) < 0.0001)
        #expect(HeatmapExpansion.cameraEase(2) == 1)
        #expect(HeatmapExpansion.rise(-0.5) == 0)
        #expect(abs(HeatmapExpansion.rise(4) - 1) < 0.0001)
    }

    @Test("Шкала строго красная, различает яркость и оставляет нулевой день серым")
    func pureRedRampPreservesLevels() {
        var previous: Float = 0
        for step in 1...HeatmapShade.steps {
            let color = HeatmapShade.color(step).resolve(in: EnvironmentValues())
            #expect(color.green == 0 && color.blue == 0)
            #expect(color.red > previous)
            previous = color.red
        }
        #expect(abs(previous - 1) < 0.0001)
        #expect(HeatmapShade.step(0, maxCount: 25) == nil)
        #expect(HeatmapShade.step(25, maxCount: 25) == HeatmapShade.steps)
        #expect(HeatmapShade.step(1, maxCount: 1) == HeatmapShade.steps)
        #expect(HeatmapShade.step(1, maxCount: 25)! < HeatmapShade.step(7, maxCount: 25)!)
        #expect(HeatmapShade.step(7, maxCount: 25)! < HeatmapShade.step(25, maxCount: 25)!)
    }

    @Test("Финальный кадр полностью объёмный, плоский — полностью плоский")
    func endpointsMatchTheIntendedLooks() {
        #expect(HeatmapExpansion.cameraEase(0) < 0.0001)
        #expect(HeatmapExpansion.cameraEase(1) > 0.9999)
        #expect(HeatmapExpansion.rise(0) == 0)
        #expect(HeatmapExpansion.rise(1) == 1)
    }
}