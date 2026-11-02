import Foundation
import CoreGraphics
import Observation

/// Состояние режима подсказок. Включён ли режим и какие сценарии пройдены —
/// в UserDefaults, только на этом устройстве (сервер не участвует).
@MainActor
@Observable
final class HintCenter {
    static let shared = HintCenter()

    static let enabledKey = "hints.enabled"
    static let completedKey = "hints.completed"

    private let defaults: UserDefaults
    let scenarios: [HintScenario]

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled { active = nil } else { tryAutoStart() }
        }
    }
    private(set) var completed: Set<String>
    /// Идущий сценарий и его шаг.
    private(set) var active: (scenario: String, step: String)?
    /// Рамки привязанных элементов в координатах окна.
    private(set) var anchors: [String: CGRect] = [:]
    /// Рамка карточки подсказки: окно оверлея принимает касания только в ней,
    /// остальные уходят в приложение.
    @ObservationIgnored var cardFrame: CGRect = .zero

    init(defaults: UserDefaults = .standard, scenarios: [HintScenario] = HintScenarios.all) {
        self.defaults = defaults
        self.scenarios = scenarios
        // Режим подсказок — это обучение, а не украшение: включается сам
        // (владелец 02.11.2026). Явный выбор владельца уважается — если ключ
        // записан, берём его; если нет — включаем. Выключить — один тап в
        // «Настройки → Подсказки», и выбор переживает перезапуск.
        isEnabled = (defaults.object(forKey: Self.enabledKey) as? Bool) ?? true
        completed = Set(defaults.stringArray(forKey: Self.completedKey) ?? [])
    }

    var currentStep: HintStep? {
        guard let active, let scenario = scenario(active.scenario) else { return nil }
        return scenario.steps[active.step]
    }

    var currentScenario: HintScenario? { active.flatMap { scenario($0.scenario) } }

    func scenario(_ id: String) -> HintScenario? { scenarios.first { $0.id == id } }

    // MARK: Якоря

    func report(anchor id: String, frame: CGRect) {
        if anchors[id] == frame { return }
        anchors[id] = frame
        tryAutoStart()
    }

    func remove(anchor id: String) { anchors[id] = nil }

    /// Нажали на подсвеченный элемент — шаг засчитан.
    func tapped(anchor id: String) {
        guard let step = currentStep, step.anchor == id, step.advancesOnTap else { return }
        go(step.next)
    }

    // MARK: Ход сценария

    /// Сценарий начинается сам, как только на экране появился его первый
    /// элемент, если режим включён и сценарий ещё не пройден.
    private func tryAutoStart() {
        guard isEnabled, active == nil else { return }
        for scenario in scenarios where !completed.contains(scenario.id) {
            guard let anchor = scenario.steps[scenario.start]?.anchor, anchors[anchor] != nil else { continue }
            active = (scenario.id, scenario.start)
            return
        }
    }

    func start(_ id: String) {
        guard let scenario = scenario(id) else { return }
        isEnabled = true
        active = (scenario.id, scenario.start)
    }

    func next() { go(currentStep?.next) }

    func choose(_ branch: HintBranch) { go(branch.next) }

    /// «Пропустить» — сценарий считается пройденным.
    func finish() {
        if let id = active?.scenario { markCompleted(id) }
        active = nil
    }

    func restart(_ id: String) {
        completed.remove(id)
        save()
        start(id)
    }

    func resetAll() {
        completed = []
        save()
        active = nil
        tryAutoStart()
    }

    private func go(_ step: String?) {
        guard let active else { return }
        if let step, scenario(active.scenario)?.steps[step] != nil {
            self.active = (active.scenario, step)
        } else {
            finish()
        }
    }

    private func markCompleted(_ id: String) {
        completed.insert(id)
        save()
    }

    private func save() { defaults.set(completed.sorted(), forKey: Self.completedKey) }
}
