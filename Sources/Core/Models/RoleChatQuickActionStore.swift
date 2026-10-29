import Foundation
import Observation

/// Правки быстрых действий, сделанные владельцем (владелец 29.10.2026).
///
/// Хранятся на устройстве по ключу роли: это подсказка для личного чата, а не
/// настройка роли. Правки одного устройства не видны на другом — если понадобится
/// общий синхрон, понадобится поле на сервере.
@MainActor
@Observable
final class RoleChatQuickActionStore {
    private(set) var overridesByRole: [String: RoleChatQuickActionOverrides] = [:]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        overridesByRole = Self.loadAll(defaults: defaults)
    }

    /// Правки роли.
    func overrides(for roleKey: String) -> RoleChatQuickActionOverrides {
        overridesByRole[roleKey] ?? [:]
    }

    /// Сохранить правку карточки. Пустая правка (пустые поля) — снимает
    /// переопределение: карточка возвращается к штатной.
    func setOverride(_ override: RoleChatQuickActionOverride, index: Int, roleKey: String) {
        var current = overrides(for: roleKey)
        if override.isEmpty {
            current.removeValue(forKey: index)
        } else {
            current[index] = override
        }
        overridesByRole[roleKey] = current
        persist(roleKey: roleKey, overrides: current)
    }

    /// Вернуть карточку к штатной.
    func reset(index: Int, roleKey: String) {
        setOverride(RoleChatQuickActionOverride(), index: index, roleKey: roleKey)
    }

    /// Есть ли правки у роли — тогда в меню есть смысл показывать «Сбросить».
    func hasOverrides(for roleKey: String) -> Bool {
        !overrides(for: roleKey).isEmpty
    }

    private func persist(roleKey: String, overrides: RoleChatQuickActionOverrides) {
        let key = RoleChatQuickActions.storageKey(roleKey: roleKey)
        guard !overrides.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        let payload = overrides.mapValues { [$0.name ?? "", $0.prompt ?? ""] }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        defaults.set(data, forKey: key)
    }

    private static func loadAll(defaults: UserDefaults) -> [String: RoleChatQuickActionOverrides] {
        var result: [String: RoleChatQuickActionOverrides] = [:]
        for (key, value) in defaults.dictionaryRepresentation() {
            guard key.hasPrefix("taskflow_quick_actions."), let data = value as? Data else { continue }
            guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] else { continue }
            let roleKey = String(key.dropFirst("taskflow_quick_actions.".count))
            var overrides: RoleChatQuickActionOverrides = [:]
            for (indexText, pair) in raw {
                guard let index = Int(indexText), pair.count >= 2 else { continue }
                let name = pair[0].isEmpty ? nil : pair[0]
                let prompt = pair[1].isEmpty ? nil : pair[1]
                let override = RoleChatQuickActionOverride(name: name, prompt: prompt)
                if !override.isEmpty { overrides[index] = override }
            }
            if !overrides.isEmpty { result[roleKey] = overrides }
        }
        return result
    }
}
