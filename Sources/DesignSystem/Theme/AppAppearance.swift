import SwiftUI

/// Один сохранённый выбор для всего приложения, включая модальные экраны.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "taskflow_appearance"
    static let legacyStorageKey = "taskflow_settings_dark_theme"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Как в системе"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// Сохраняет старый выбор тумблера; без выбора остаётся привычная тёмная тема.
    @discardableResult
    static func migratePreference(in defaults: UserDefaults = .standard) -> AppAppearance {
        if let raw = defaults.string(forKey: storageKey) {
            return AppAppearance(rawValue: raw) ?? .dark
        }
        let legacy = defaults.object(forKey: legacyStorageKey) as? Bool
        let appearance: AppAppearance = legacy == false ? .light : .dark
        defaults.set(appearance.rawValue, forKey: storageKey)
        return appearance
    }
}
