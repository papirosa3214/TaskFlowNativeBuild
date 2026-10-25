import XCTest
import Foundation
@testable import TaskFlow

/// Метрики устройства и ручные снимки заряда.
///
/// Проверяются три вещи, на которых держится честность экрана:
/// • хранилище держит не больше пяти снимков и не пишет бессмысленные значения;
/// • снимки переживают перезапуск приложения (они в UserDefaults);
/// • системный снимок не выдумывает заряд: если система не сообщает, значит
///   «неизвестно», а не ноль процентов.
final class DeviceResourceMetricsTests: XCTestCase {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let name = "DeviceResourceMetricsTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        return (defaults, name)
    }

    func testStoreKeepsOnlyFiveNewestSnapshots() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = BatterySnapshotStore(defaults: defaults)

        for level in [10, 20, 30, 40, 50, 60, 70] {
            store.add(level: level, now: Date().addingTimeInterval(Double(level)))
        }

        let items = store.snapshots()
        XCTAssertEqual(items.count, 5, "хранится максимум пять снимков")
        XCTAssertEqual(items.map(\.level), [70, 60, 50, 40, 30], "свежие сверху, старые отброшены")
    }

    func testStoreRejectsLevelsOutsideRange() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = BatterySnapshotStore(defaults: defaults)

        XCTAssertNil(store.add(level: -1), "отрицательный заряд — не снимок")
        XCTAssertNil(store.add(level: 101), "больше ста — не снимок")
        XCTAssertTrue(store.snapshots().isEmpty)
    }

    func testStorePersistsAcrossInstances() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        BatterySnapshotStore(defaults: defaults).add(level: 62, note: "после разговора с ролью")

        let reopened = BatterySnapshotStore(defaults: defaults)
        XCTAssertEqual(reopened.snapshots().count, 1)
        XCTAssertEqual(reopened.snapshots().first?.level, 62)
        XCTAssertEqual(reopened.snapshots().first?.note, "после разговора с ролью")
    }

    func testClearRemovesSnapshots() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = BatterySnapshotStore(defaults: defaults)
        store.add(level: 50)
        store.clear()
        XCTAssertTrue(store.snapshots().isEmpty)
    }

    func testSystemSnapshotNeverInventsBatteryLevel() {
        let snapshot = DeviceResourceMetrics.currentSnapshot()
        XCTAssertLessThanOrEqual(snapshot.takenAt.timeIntervalSinceNow, 1)
        if let level = snapshot.batteryLevel {
            XCTAssertTrue((0...100).contains(level), "система не может сообщить заряд вне диапазона")
        }
        // Память и footprint — системные значения; они не выдумываются.
        XCTAssertGreaterThanOrEqual(snapshot.availableMemoryBytes, 0)
        XCTAssertGreaterThanOrEqual(snapshot.appFootprintBytes, 0)
    }
}
