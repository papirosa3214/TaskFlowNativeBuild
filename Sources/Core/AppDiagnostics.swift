import Foundation
import UIKit

/// Counters are deliberately not observable: a 60 Hz pacer must not invalidate settings/UI.
/// No sampling timer. Persistence is bounded to lifecycle/low-frequency transitions.
final class AppDiagnostics: @unchecked Sendable {
    static let shared = AppDiagnostics()
    static let storageKey = "app.activityDiagnostics.v1"
    static let baselineKey = "app.activityDiagnostics.baseline.v1"

    enum Work: String, Codable, CaseIterable, Sendable {
        case reply, thinking, socket, watchdog, location, http
        var title: String {
            switch self {
            case .reply: "Очередь ответа"
            case .thinking: "Очередь размышлений"
            case .socket: "Соединение с сервером"
            case .watchdog: "Проверка соединения"
            case .location: "Фон островка"
            case .http: "Запрос к серверу"
            }
        }
    }

    enum Counter: String, Codable, CaseIterable, Sendable {
        case ticks, updates, draws, wakes, sleeps, messages, reconnects, watchdogChecks, requests, bytes, locationEvents
    }

    struct Entry: Codable, Identifiable, Sendable {
        var id = UUID()
        let date: Date
        let text: String
        let background: Bool
    }

    struct Saved: Codable, Sendable {
        var since = Date()
        var totals: [String: Int] = [:]
        var backgroundTotals: [String: Int] = [:]
        var events: [Entry] = []
    }

    /// Точка отсчёта: снимок счётчиков в момент, когда приложение вернулось на
    /// экран. Нужна, чтобы отчёт и экран показывали прирост за текущий сеанс, а
    /// не только накопленный итог за недели (владелец 18.10.2026: «понимать,
    /// что вот сейчас что-то растёт»). Отдельный ключ, а не поле `Saved`, чтобы
    /// старый сохранённый снимок читался без изменений.
    struct Baseline: Codable, Sendable {
        var at: Date
        var totals: [String: Int] = [:]
        var backgroundTotals: [String: Int] = [:]
    }

    struct Snapshot: Sendable {
        let saved: Saved
        let active: [Work: Int]
        let background: Bool
        let lastEventAt: Date?
        let baseline: Baseline
        func count(_ counter: Counter, backgroundOnly: Bool = false) -> Int {
            (backgroundOnly ? saved.backgroundTotals : saved.totals)[counter.rawValue, default: 0]
        }
        var activeQueues: Int { active[.reply, default: 0] + active[.thinking, default: 0] }
    }

    private let lock = NSLock()
    private let defaults: UserDefaults?
    private var saved: Saved
    private var baseline: Baseline
    private var active: [UUID: Work] = [:]
    private var background = false
    private var lastEventAt: Date?
    private var lastCheckpoint = Date.distantPast
    @MainActor private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.storageKey),
           let restored = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = restored
        } else { saved = Saved() }
        if let data = defaults?.data(forKey: Self.baselineKey),
           let restored = try? JSONDecoder().decode(Baseline.self, from: data) {
            baseline = restored
        } else {
            // Отчёта ещё не было — отсчёт с начала сбора счётчиков.
            baseline = Baseline(at: saved.since)
        }
    }

    @discardableResult
    func begin(_ work: Work) -> UUID {
        lock.lock(); defer { lock.unlock() }
        let id = UUID()
        active[id] = work
        if work == .reply || work == .thinking { incrementLocked(.wakes) }
        if work == .http { incrementLocked(.requests) }
        if work != .http {
            eventLocked(work.title + ": работает")
            checkpointLocked(force: false)
        }
        return id
    }

    func end(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        guard let work = active.removeValue(forKey: id) else { return }
        if work == .reply || work == .thinking { incrementLocked(.sleeps) }
        if work != .http {
            eventLocked(work.title + ": остановлен")
            checkpointLocked(force: false)
        }
    }

    func increment(_ counter: Counter, by amount: Int = 1) {
        lock.lock(); defer { lock.unlock() }
        incrementLocked(counter, by: amount)
        lastEventAt = Date()
    }

    func setBackground(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard background != value else { return }
        background = value
        eventLocked(value ? "Приложение ушло в фон" : "Приложение открыто")
        // Возврат на экран — начало нового отсчёта: в отчёте видно, сколько
        // стоило то, что владелец делал в приложении в этот раз.
        if !value { markBaselineLocked() }
        checkpointLocked(force: true)
    }

    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        var counts: [Work: Int] = [:]
        for work in active.values { counts[work, default: 0] += 1 }
        return Snapshot(
            saved: saved, active: counts, background: background,
            lastEventAt: lastEventAt, baseline: baseline
        )
    }

    func checkpoint() {
        lock.lock(); defer { lock.unlock() }
        checkpointLocked(force: true)
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        saved = Saved()
        eventLocked("Счётчики сброшены")
        // Active work remains registered so a reset cannot hide a running loop.
        checkpointLocked(force: true)
        markBaselineLocked()
    }

    /// Отметить начало отсчёта по текущему состоянию счётчиков.
    private func markBaselineLocked() {
        baseline = Baseline(at: Date(), totals: saved.totals, backgroundTotals: saved.backgroundTotals)
        guard let defaults, let data = try? JSONEncoder().encode(baseline) else { return }
        defaults.set(data, forKey: Self.baselineKey)
    }

    private func incrementLocked(_ counter: Counter, by amount: Int = 1) {
        saved.totals[counter.rawValue, default: 0] += amount
        if background { saved.backgroundTotals[counter.rawValue, default: 0] += amount }
    }

    private func eventLocked(_ text: String) {
        let now = Date()
        lastEventAt = now
        saved.events.append(Entry(date: now, text: text, background: background))
        if saved.events.count > 80 { saved.events.removeFirst(saved.events.count - 80) }
    }

    private func checkpointLocked(force: Bool) {
        guard force || Date().timeIntervalSince(lastCheckpoint) >= 30 else { return }
        guard let defaults, let data = try? JSONEncoder().encode(saved) else { return }
        defaults.set(data, forKey: Self.storageKey)
        lastCheckpoint = Date()
    }

    @MainActor
    func startMonitoring() {
        guard observers.isEmpty else { return }
        setBackground(UIApplication.shared.applicationState == .background)
        lock.lock()
        eventLocked("Диагностика запущена")
        // Новый запуск — новый отсчёт для прироста в отчёте.
        markBaselineLocked()
        checkpointLocked(force: true)
        lock.unlock()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setBackground(true)
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setBackground(false)
        })
        observers.append(center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.checkpoint()
        })
    }

    /// Текст для «Поделиться». Разбор — в `DiagnosticsReport`: он же считает
    /// скорости, метки и группы, чтобы отчёт читался сам, без разбора цифр.
    func report() -> String {
        let data = snapshot()
        return DiagnosticsReport(snapshot: data).text(events: data.saved.events)
    }
}
