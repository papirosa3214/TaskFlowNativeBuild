import XCTest
import Foundation
@testable import TaskFlow

/// Диагностика должна быть диагностикой — LOCK-DIAGNOSTICS-VERDICTS-20261018.
///
/// Владелец 18.10.2026: «дополни эту диагностику, чтобы диагностика была
/// диагностикой… я просто скинул эту диагностику, и сразу станет понятно, что
/// там какие проблемы; счётчики скомпоновать, чтобы понимать, что вот сейчас
/// что-то растёт — это плохо, а это в норме».
///
/// Здесь проверяется чистая логика отчёта (`DiagnosticsReport`): пороги,
/// прирост от точки отсчёта, скорости, фоновое правило, группы и текст. Плюс
/// сторож мёртвых счётчиков: счётчик, который нигде не увеличивается,
/// показывает застрявшее число и врёт — так было с «Отрисовками текста» до
/// 18.10.2026 (`increment(.draws)` не вызывался нигде).
final class DiagnosticsReportTests: XCTestCase {

    // MARK: - Сборка снимка

    private func snapshot(
        totals: [AppDiagnostics.Counter: Int] = [:],
        backgroundTotals: [AppDiagnostics.Counter: Int] = [:],
        baselineTotals: [AppDiagnostics.Counter: Int] = [:],
        baselineBackgroundTotals: [AppDiagnostics.Counter: Int] = [:],
        baselineAt: Date,
        active: [AppDiagnostics.Work: Int] = [:],
        background: Bool = false
    ) -> AppDiagnostics.Snapshot {
        var saved = AppDiagnostics.Saved()
        saved.since = baselineAt.addingTimeInterval(-86_400)
        for (key, value) in totals { saved.totals[key.rawValue] = value }
        for (key, value) in backgroundTotals { saved.backgroundTotals[key.rawValue] = value }
        var baseline = AppDiagnostics.Baseline(at: baselineAt)
        for (key, value) in baselineTotals { baseline.totals[key.rawValue] = value }
        for (key, value) in baselineBackgroundTotals { baseline.backgroundTotals[key.rawValue] = value }
        return AppDiagnostics.Snapshot(
            saved: saved, active: active, background: background,
            lastEventAt: nil, baseline: baseline
        )
    }

    // MARK: - Пороги и метки

    func testMarkBandsFollowTheLimit() {
        XCTAssertEqual(DiagnosticsReport.mark(perMinute: 0, normal: 12, alarm: 40), .ok)
        XCTAssertEqual(DiagnosticsReport.mark(perMinute: 12, normal: 12, alarm: 40), .ok)
        XCTAssertEqual(DiagnosticsReport.mark(perMinute: 12.1, normal: 12, alarm: 40), .attention)
        XCTAssertEqual(DiagnosticsReport.mark(perMinute: 40, normal: 12, alarm: 40), .attention)
        XCTAssertEqual(DiagnosticsReport.mark(perMinute: 40.1, normal: 12, alarm: 40), .alarm)
    }

    func testLocationEventsAreNeverNormalWhenGrowing() {
        // Предел нормы ноль: любое движение геопозиции — уже внимание.
        XCTAssertEqual(DiagnosticsReport.mark(perMinute: 0, normal: 0, alarm: 5), .ok)
        XCTAssertEqual(DiagnosticsReport.mark(perMinute: 1, normal: 0, alarm: 5), .attention)
        XCTAssertEqual(DiagnosticsReport.mark(perMinute: 6, normal: 0, alarm: 5), .alarm)
    }

    // MARK: - Прирост и скорость

    func testDeltaIsCountedFromBaselineNotFromTotal() throws {
        let now = Date()
        let snapshot = snapshot(
            totals: [.requests: 42_449],
            baselineTotals: [.requests: 42_394],
            baselineAt: now.addingTimeInterval(-12 * 60)
        )
        let report = DiagnosticsReport(snapshot: snapshot, now: now)
        let row = try XCTUnwrap(report.rows.first { $0.id == "requests" })
        XCTAssertEqual(row.total, 42_449)
        XCTAssertEqual(row.delta, 55)
        XCTAssertEqual(row.perMinute, 55.0 / 12, accuracy: 0.01)
        XCTAssertEqual(row.mark, .ok)
    }

    func testRateIsNotInflatedByAVeryShortWindow() {
        let now = Date()
        let snapshot = snapshot(
            totals: [.requests: 3],
            baselineAt: now.addingTimeInterval(-10)
        )
        let report = DiagnosticsReport(snapshot: snapshot, now: now)
        let row = report.rows.first { $0.id == "requests" }
        // Десять секунд не раздуваются в 18/мин: скорость считается не меньше
        // чем за минуту, иначе один запрос выглядел бы тревогой.
        XCTAssertEqual(row?.perMinute ?? 0, 3, accuracy: 0.001)
    }

    func testDeltaNeverGoesNegativeAfterReset() {
        let now = Date()
        let snapshot = snapshot(
            totals: [.requests: 1],
            baselineTotals: [.requests: 99],
            baselineAt: now.addingTimeInterval(-60)
        )
        XCTAssertEqual(DiagnosticsReport(snapshot: snapshot, now: now).rows.first { $0.id == "requests" }?.delta, 0)
    }

    // MARK: - Фон

    func testBackgroundWorkIsFineOnlyWhenIdle() {
        XCTAssertEqual(DiagnosticsReport.backgroundMark(backgroundDelta: 0, islandActive: false), .ok)
        XCTAssertEqual(DiagnosticsReport.backgroundMark(backgroundDelta: 0, islandActive: true), .ok)
        XCTAssertEqual(DiagnosticsReport.backgroundMark(backgroundDelta: 12, islandActive: true), .attention)
        // Приложение жило в фоне, а островка нет — это уже сигнал тревоги.
        XCTAssertEqual(DiagnosticsReport.backgroundMark(backgroundDelta: 12, islandActive: false), .alarm)
    }

    // MARK: - Группы и итог

    func testGroupsAreInFixedOrderAndCoverTheCounters() {
        let report = DiagnosticsReport(snapshot: snapshot(baselineAt: Date()))
        XCTAssertEqual(report.groups.map(\.id), ["text", "network", "background"])
        XCTAssertEqual(report.groups.map(\.title), ["Текст ответа", "Сеть", "Фон"])
        for id in ["ticks", "draws", "updates", "wakes", "sleeps", "requests", "bytes", "messages",
                   "watchdogChecks", "reconnects", "locationEvents"] {
            XCTAssertTrue(report.rows.contains { $0.id == id }, "нет строки счётчика \(id)")
        }
        XCTAssertEqual(report.mark, .ok)
        XCTAssertTrue(report.verdictLine.contains("всё в норме"))
    }

    func testWorstMarkWinsAndIsNamedInTheReport() {
        let now = Date()
        let snapshot = snapshot(
            totals: [.requests: 100, .locationEvents: 2],
            backgroundTotals: [.requests: 12],
            baselineAt: now.addingTimeInterval(-60)
        )
        let report = DiagnosticsReport(snapshot: snapshot, now: now)
        XCTAssertEqual(report.mark, .alarm)
        XCTAssertGreaterThanOrEqual(report.alarmCount, 2)
        let text = report.text()
        XCTAssertTrue(text.contains("ИТОГ:"))
        XCTAssertTrue(text.contains("тревожно"))
        XCTAssertTrue(text.contains("[Сеть]"))
        XCTAssertTrue(text.contains("Запросы к серверу"))
        XCTAssertTrue(text.contains("События геопозиции"))
        // Прирост виден рядом с итогом, а не только накопленное число.
        XCTAssertTrue(text.contains("за отсчёт +100"))
    }

    func testBackgroundRowIsPickedUpByTheReport() {
        let now = Date()
        let snapshot = snapshot(
            backgroundTotals: [.messages: 30],
            baselineAt: now.addingTimeInterval(-60),
            active: [.location: 1]
        )
        let report = DiagnosticsReport(snapshot: snapshot, now: now)
        let background = report.groups.first { $0.id == "background" }
        XCTAssertEqual(background?.mark, .attention)
        XCTAssertEqual(background?.rows.first { $0.id == "background-work" }?.delta, 30)
    }

    // MARK: - Состояние «сейчас»

    func testStateLineDescribesRunningWork() {
        let line = DiagnosticsReport.stateLine(snapshot(
            baselineAt: Date(),
            active: [.reply: 1, .socket: 1, .location: 1]
        ))
        XCTAssertTrue(line.contains("очереди текста работают"))
        XCTAssertTrue(line.contains("соединение работает"))
        XCTAssertTrue(line.contains("держится фон островка"))
    }

    // MARK: - Устройство: источники, пороги, топ и ручные снимки

    private func device(
        battery: Int? = 62,
        thermal: ProcessInfo.ThermalState = .nominal,
        lowPower: Bool = false,
        available: UInt64 = 84 * 1_048_576,
        footprint: UInt64 = 12_400_000
    ) -> DeviceResourceSnapshot {
        DeviceResourceSnapshot(
            takenAt: Date(),
            thermalState: thermal,
            lowPowerModeEnabled: lowPower,
            batteryLevel: battery,
            batteryState: .unplugged,
            availableMemoryBytes: available,
            appFootprintBytes: footprint
        )
    }

    func testDeviceFactsCarrySourceAndMarks() {
        let report = DiagnosticsReport(snapshot: snapshot(baselineAt: Date()), device: device())
        XCTAssertEqual(report.deviceFacts.count, 5)
        // У каждого значения виден источник: системное измерение, а не счётчик.
        XCTAssertTrue(report.deviceFacts.allSatisfy { $0.source == "системное измерение" })
        XCTAssertEqual(report.deviceFacts.first { $0.id == "battery" }?.value, "62%")
        XCTAssertEqual(report.deviceFacts.first { $0.id == "battery" }?.mark, .ok)
        XCTAssertEqual(report.deviceFacts.first { $0.id == "thermal" }?.value, "норма")
        XCTAssertEqual(report.deviceFacts.first { $0.id == "low-power" }?.value, "выключен")
        XCTAssertTrue(report.text().contains("[Устройство]"))
    }

    func testDeviceMarksFollowRealThresholds() {
        // iOS просит беречь батарею на 20 % и предупреждает на 10 %.
        XCTAssertEqual(DiagnosticsReport.batteryMark(20), .ok)
        XCTAssertEqual(DiagnosticsReport.batteryMark(19), .attention)
        XCTAssertEqual(DiagnosticsReport.batteryMark(9), .alarm)
        XCTAssertEqual(DiagnosticsReport.batteryMark(nil), .ok)
        // Тепло: serious — система сама ограничивает нагрузку.
        XCTAssertEqual(DiagnosticsReport.thermalMark(.nominal), .ok)
        XCTAssertEqual(DiagnosticsReport.thermalMark(.fair), .ok)
        XCTAssertEqual(DiagnosticsReport.thermalMark(.serious), .attention)
        XCTAssertEqual(DiagnosticsReport.thermalMark(.critical), .alarm)
        // Память: ниже 100 МБ тесно, ниже 50 МБ iOS снимает фоновые приложения.
        XCTAssertEqual(DiagnosticsReport.memoryMark(84 * 1_048_576), .ok)
        XCTAssertEqual(DiagnosticsReport.memoryMark(60 * 1_048_576), .attention)
        XCTAssertEqual(DiagnosticsReport.memoryMark(20 * 1_048_576), .alarm)
    }

    func testTopConsumersAreThreeFastestNonByteCounters() {
        let now = Date()
        let snapshot = snapshot(
            totals: [.ticks: 300, .wakes: 25, .messages: 10, .requests: 5, .bytes: 10_000_000],
            baselineAt: now.addingTimeInterval(-60)
        )
        let report = DiagnosticsReport(snapshot: snapshot, now: now)
        XCTAssertEqual(report.topConsumers.map(\.id), ["ticks", "wakes", "messages"])
        // Байты с тактами не сравниваются: у них разные единицы.
        XCTAssertFalse(report.topConsumers.contains { $0.isBytes })
        XCTAssertTrue(report.text().contains("[Кто подъедает]"))
    }

    func testBatteryDeltaNeedsTwoManualSnapshots() {
        let now = Date()
        let report = DiagnosticsReport(
            snapshot: snapshot(baselineAt: now),
            batterySnapshots: [BatterySnapshot(date: now, level: 62)]
        )
        XCTAssertNil(report.batteryDelta, "по одному снимку расход не считается")
    }

    func testBatteryDeltaComparesTwoManualSnapshots() throws {
        let now = Date()
        let previous = BatterySnapshot(date: now.addingTimeInterval(-4 * 3600 - 12 * 60), level: 62)
        let latest = BatterySnapshot(date: now, level: 54)
        let report = DiagnosticsReport(
            snapshot: snapshot(baselineAt: now),
            batterySnapshots: [latest, previous]
        )
        let delta = try XCTUnwrap(report.batteryDelta)
        XCTAssertEqual(delta.percentChange, -8)
        XCTAssertEqual(delta.previous.level, 62)
        XCTAssertEqual(delta.latest.level, 54)
        XCTAssertEqual(DiagnosticsReport.batteryText(delta), "62% → 54% за 4 ч 12 мин, −8%")
        let text = report.text()
        XCTAssertTrue(text.contains("[Расход батареи]"))
        XCTAssertTrue(text.contains("ручные снимки владельца"))
    }

    // MARK: - Сторож мёртвых счётчиков

    /// Каждый счётчик обязан где-то увеличиваться. Счётчик без вызова
    /// `increment` показывает застрявшее значение и вводит владельца в
    /// заблуждение — ровно так было с «Отрисовками текста» (455 524 в отчёте
    /// от 18.10.2026 при нулевом приросте за сеанс).
    func testEveryCounterIsActuallyIncrementedInSources() throws {
        let root = try XCTUnwrap(Self.sourcesRoot, "не найден корень Sources рядом с Tests")
        let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        var code = ""
        var fileCount = 0
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            fileCount += 1
            code += (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        XCTAssertGreaterThan(fileCount, 100, "Sources почти пуст — тест ничего не проверяет")

        for counter in AppDiagnostics.Counter.allCases {
            let direct = "increment(.\(counter.rawValue)"
            let locked = "incrementLocked(.\(counter.rawValue)"
            XCTAssertTrue(
                code.contains(direct) || code.contains(locked),
                "счётчик .\(counter.rawValue) нигде не увеличивается — он мёртвый и врёт в отчёте"
            )
        }
    }

    /// Корень исходников: рядом с папкой `Tests`.
    private static var sourcesRoot: URL? {
        // #filePath = <repo>/Tests/DiagnosticsReportTests.swift
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }
}
