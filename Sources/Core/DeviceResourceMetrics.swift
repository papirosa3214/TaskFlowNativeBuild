import Foundation
import UIKit
import Darwin.Mach

/// Снимок состояния устройства в момент чтения.
///
/// Источник каждого значения — системный замер iOS. Ничего здесь не
/// вычисляется «на глаз»: заряд, тепло, режим экономии, свободная память и
/// размер приложения в памяти берутся у системы.
///
/// Снимок читается по требованию (открытие экрана, кнопка «Снимок»), а не по
/// таймеру: постоянный опрос системных метрик сам по себе жрёт заряд.
/// Второй источник — ручные снимки заряда, которые владелец делает сам; их
/// хранит `BatterySnapshotStore`.
struct DeviceResourceSnapshot: Sendable {
    /// Когда снят снимок.
    let takenAt: Date
    /// Тепло устройства: nominal / fair / serious / critical.
    let thermalState: ProcessInfo.ThermalState
    /// Включён ли режим экономии энергии.
    let lowPowerModeEnabled: Bool
    /// Текущий системный заряд, 0...100. `nil` — система не отдаёт значение
    /// (симулятор, устройство без батареи). Это заряд устройства, а НЕ расход
    /// батареи приложением: iOS такого процента не сообщает.
    let batteryLevel: Int?
    /// Состояние батареи: charging / full / unplugged / unknown.
    let batteryState: UIDevice.BatteryState
    /// Сколько памяти может взять приложение, а не сколько памяти занято.
    let availableMemoryBytes: UInt64
    /// Физический footprint приложения в памяти (Mach, без аллокаций).
    let appFootprintBytes: UInt64
}

/// Системные метрики устройства: чтение по требованию, без таймера.
enum DeviceResourceMetrics {
    /// Снять текущий снимок устройства.
    static func currentSnapshot(now: Date = Date()) -> DeviceResourceSnapshot {
        let battery = readBattery()
        return DeviceResourceSnapshot(
            takenAt: now,
            thermalState: ProcessInfo.processInfo.thermalState,
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            batteryLevel: battery.level,
            batteryState: battery.state,
            availableMemoryBytes: availableMemoryBytes(),
            appFootprintBytes: appFootprintBytes()
        )
    }

    // MARK: - Заряд

    /// Системный заряд. Мониторинг батареи включается на время чтения и сразу
    /// выключается: постоянно включённый мониторинг — это постоянный расход.
    private static func readBattery() -> (level: Int?, state: UIDevice.BatteryState) {
        let device = UIDevice.current
        let wasEnabled = device.isBatteryMonitoringEnabled
        if !wasEnabled { device.isBatteryMonitoringEnabled = true }
        defer { if !wasEnabled { device.isBatteryMonitoringEnabled = false } }
        let raw = device.batteryLevel
        let state = device.batteryState
        guard raw >= 0 else { return (nil, state) }
        return (Int((raw * 100).rounded()), state)
    }

    // MARK: - Память

    /// Сколько памяти свободно в системе. Считаем через Mach: без аллокаций
    /// и без зависимости от внутренних API, которые меняются от версии к
    /// версии. Это «свободно в системе», а не «сколько приложению разрешено»:
    /// лимит jetsam приложения iOS отдельно не отдаёт.
    private static func availableMemoryBytes() -> UInt64 {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        // Размер страницы берём из Mach: поля `page_size` у
        // `vm_statistics64_data_t` нет (ошибка компиляции), а `host_page_size`
        // отдаёт точный размер страницы текущей системы.
        var pageSize: vm_size_t = 0
        _ = host_page_size(mach_host_self(), &pageSize)
        let bytes = pageSize == 0 ? 4096 : UInt64(pageSize)
        return UInt64(stats.free_count) * bytes
    }

    /// Физический footprint приложения. Читается напрямую из Mach, без
    /// аллокаций в горячем пути и без создания снимков задачи.
    private static func appFootprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.phys_footprint)
    }
}

/// Ручной снимок заряда: владелец открыл «Настройки → Батарея» и записал,
/// сколько процентов осталось. Только так можно честно сказать «минус 8 % за
/// четыре часа» — iOS не сообщает, сколько батареи съело приложение.
struct BatterySnapshot: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    /// Когда сделан снимок.
    let date: Date
    /// Заряд в процентах, 0...100.
    let level: Int
    /// Необязательная пометка владельца («после разговора с ролью»).
    let note: String?

    init(id: UUID = UUID(), date: Date, level: Int, note: String? = nil) {
        self.id = id
        self.date = date
        self.level = level
        self.note = note
    }
}

/// Хранилище ручных снимков заряда.
///
/// Ключ `app.batterySnapshots.v1`, не больше пяти записей: это не журнал, а
/// опорные точки для сравнения «было — стало». Хранятся локально, на
/// устройстве; никуда не отправляются.
final class BatterySnapshotStore: @unchecked Sendable {
    static let storageKey = "app.batterySnapshots.v1"
    /// Больше пяти снимков не держим: дальше начинается шум.
    static let limit = 5

    private let defaults: UserDefaults?
    private let lock = NSLock()

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
    }

    /// Снимки, свежие сверху.
    func snapshots() -> [BatterySnapshot] {
        lock.lock(); defer { lock.unlock() }
        return loadLocked()
    }

    /// Добавить снимок. Возвращает `nil`, если значение заряда непригодно:
    /// вне 0...100 писать нечего (в том числе системное «неизвестно»).
    @discardableResult
    func add(level: Int, note: String? = nil, now: Date = Date()) -> BatterySnapshot? {
        guard (0...100).contains(level) else { return nil }
        lock.lock(); defer { lock.unlock() }
        var items = loadLocked()
        let snapshot = BatterySnapshot(date: now, level: level, note: note)
        items.insert(snapshot, at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
        saveLocked(items)
        return snapshot
    }

    /// Убрать все ручные снимки.
    func clear() {
        lock.lock(); defer { lock.unlock() }
        defaults?.removeObject(forKey: Self.storageKey)
    }

    private func loadLocked() -> [BatterySnapshot] {
        guard let data = defaults?.data(forKey: Self.storageKey),
              let items = try? JSONDecoder().decode([BatterySnapshot].self, from: data)
        else { return [] }
        return items
    }

    private func saveLocked(_ items: [BatterySnapshot]) {
        guard let defaults, let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
